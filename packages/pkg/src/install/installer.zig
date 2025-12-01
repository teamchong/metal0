//! Wheel Installer
//!
//! Downloads and installs Python wheel packages to site-packages.
//! Uses HTTP/2 multiplexing for parallel downloads.
//!
//! ## Wheel Format (PEP 427)
//! A wheel is a ZIP archive with:
//! - {dist}-{version}.dist-info/METADATA
//! - {dist}-{version}.dist-info/WHEEL
//! - {dist}-{version}.dist-info/RECORD
//! - Package files (*.py, *.so, etc.)

const std = @import("std");
const h2 = @import("h2");
const builtin = @import("builtin");
const record = @import("../parse/record.zig");

pub const InstallerError = error{
    NoWheelUrl,
    DownloadFailed,
    InvalidWheel,
    PackageNotFound,
    ExtractionFailed,
    NoSitePackages,
    OutOfMemory,
    HashMismatch,
};

/// Result of installing a package
pub const InstallResult = struct {
    name: []const u8,
    version: []const u8,
    files_installed: usize,
    size_bytes: u64,
};

/// Installer configuration
pub const InstallerConfig = struct {
    /// Target site-packages directory (auto-detect if null)
    site_packages: ?[]const u8 = null,
    /// Verify SHA256 hashes
    verify_hashes: bool = true,
    /// Show progress output
    show_progress: bool = true,
};

/// Package installer
pub const Installer = struct {
    allocator: std.mem.Allocator,
    config: InstallerConfig,
    site_packages: []const u8,

    pub fn init(allocator: std.mem.Allocator, config: InstallerConfig) !Installer {
        const site_packages = if (config.site_packages) |sp|
            try allocator.dupe(u8, sp)
        else
            try detectSitePackages(allocator);

        return .{
            .allocator = allocator,
            .config = config,
            .site_packages = site_packages,
        };
    }

    pub fn deinit(self: *Installer) void {
        self.allocator.free(self.site_packages);
    }

    /// Result of uninstalling a package
    pub const UninstallResult = struct {
        name: []const u8,
        version: []const u8,
        files_removed: usize,
    };

    /// Uninstall packages by name
    pub fn uninstallPackages(self: *Installer, names: []const []const u8) ![]UninstallResult {
        var results = std.ArrayList(UninstallResult){};
        errdefer {
            for (results.items) |r| {
                self.allocator.free(r.name);
                self.allocator.free(r.version);
            }
            results.deinit(self.allocator);
        }

        for (names) |name| {
            if (self.uninstallPackage(name)) |result| {
                try results.append(self.allocator, result);
            } else |_| {
                // Package not found - skip
            }
        }

        return try results.toOwnedSlice(self.allocator);
    }

    /// Uninstall a single package
    fn uninstallPackage(self: *Installer, name: []const u8) !UninstallResult {
        // Convert name to filesystem form (e.g., charset-normalizer -> charset_normalizer)
        var fs_name_buf: [256]u8 = undefined;
        var fs_name_len: usize = 0;
        for (name) |c| {
            fs_name_buf[fs_name_len] = if (c == '-') '_' else std.ascii.toLower(c);
            fs_name_len += 1;
        }
        const fs_name = fs_name_buf[0..fs_name_len];

        // Find dist-info directory matching the package
        var site_dir = std.fs.cwd().openDir(self.site_packages, .{ .iterate = true }) catch {
            return error.NoSitePackages;
        };
        defer site_dir.close();

        var dist_info_name: ?[]const u8 = null;
        var version: ?[]const u8 = null;
        var iter = site_dir.iterate();
        while (iter.next() catch null) |entry| {
            if (entry.kind != .directory) continue;
            if (!std.mem.endsWith(u8, entry.name, ".dist-info")) continue;

            // Parse name-version.dist-info
            const without_suffix = entry.name[0 .. entry.name.len - 10];
            const dash_pos = std.mem.lastIndexOf(u8, without_suffix, "-") orelse continue;
            const entry_name = without_suffix[0..dash_pos];

            // Compare names (case-insensitive, - == _)
            if (normalizedEql(entry_name, fs_name)) {
                dist_info_name = try self.allocator.dupe(u8, entry.name);
                version = try self.allocator.dupe(u8, without_suffix[dash_pos + 1 ..]);
                break;
            }
        }

        if (dist_info_name == null) return error.PackageNotFound;
        defer self.allocator.free(dist_info_name.?);

        // Read RECORD file
        const record_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}/RECORD", .{ self.site_packages, dist_info_name.? });
        defer self.allocator.free(record_path);

        var rec = record.parseFile(self.allocator, record_path) catch {
            // No RECORD file - just delete dist-info dir
            const dist_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.site_packages, dist_info_name.? });
            defer self.allocator.free(dist_path);
            std.fs.cwd().deleteTree(dist_path) catch {};
            return .{
                .name = try self.allocator.dupe(u8, name),
                .version = version.?,
                .files_removed = 1,
            };
        };
        defer rec.deinit();

        // Delete all files listed in RECORD
        var files_removed: usize = 0;
        for (rec.files) |file| {
            const file_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.site_packages, file.path });
            defer self.allocator.free(file_path);
            std.fs.cwd().deleteFile(file_path) catch {};
            files_removed += 1;
        }

        // Delete dist-info directory and package directory
        const dist_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.site_packages, dist_info_name.? });
        defer self.allocator.free(dist_path);
        std.fs.cwd().deleteTree(dist_path) catch {};

        const pkg_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.site_packages, fs_name });
        defer self.allocator.free(pkg_path);
        std.fs.cwd().deleteTree(pkg_path) catch {};

        return .{
            .name = try self.allocator.dupe(u8, name),
            .version = version.?,
            .files_removed = files_removed,
        };
    }

    /// Installed package info
    pub const InstalledPackage = struct {
        name: []const u8,
        version: []const u8,
    };

    /// List all installed packages
    pub fn listInstalled(self: *Installer) ![]InstalledPackage {
        var packages = std.ArrayList(InstalledPackage){};
        errdefer {
            for (packages.items) |p| {
                self.allocator.free(p.name);
                self.allocator.free(p.version);
            }
            packages.deinit(self.allocator);
        }

        var site_dir = std.fs.cwd().openDir(self.site_packages, .{ .iterate = true }) catch {
            return error.NoSitePackages;
        };
        defer site_dir.close();

        var iter = site_dir.iterate();
        while (iter.next() catch null) |entry| {
            if (entry.kind != .directory) continue;
            if (!std.mem.endsWith(u8, entry.name, ".dist-info")) continue;

            // Parse name-version.dist-info
            const without_suffix = entry.name[0 .. entry.name.len - 10];
            const dash_pos = std.mem.lastIndexOf(u8, without_suffix, "-") orelse continue;
            const name = without_suffix[0..dash_pos];
            const version = without_suffix[dash_pos + 1 ..];

            try packages.append(self.allocator, .{
                .name = try self.allocator.dupe(u8, name),
                .version = try self.allocator.dupe(u8, version),
            });
        }

        // Sort by name
        const items = try packages.toOwnedSlice(self.allocator);
        std.mem.sort(InstalledPackage, items, {}, struct {
            fn lessThan(_: void, a: InstalledPackage, b: InstalledPackage) bool {
                return std.mem.lessThan(u8, a.name, b.name);
            }
        }.lessThan);

        return items;
    }

    /// Install packages from resolved wheel URLs
    pub fn installPackages(
        self: *Installer,
        packages: []const PackageInfo,
    ) ![]InstallResult {
        if (packages.len == 0) return &[_]InstallResult{};

        // Collect URLs for download
        var pypi_urls = std.ArrayList([]const u8){};
        defer pypi_urls.deinit(self.allocator);

        var url_to_pkg = std.StringHashMap(usize).init(self.allocator);
        defer url_to_pkg.deinit();

        for (packages, 0..) |pkg, i| {
            if (pkg.wheel_url) |url| {
                try pypi_urls.append(self.allocator, url);
                try url_to_pkg.put(url, i);
            }
        }

        // Download all wheels in parallel using H2 multiplexing
        const wheel_data = try self.downloadWheelsParallel(pypi_urls.items);
        defer {
            for (wheel_data) |data| {
                if (data) |d| self.allocator.free(d);
            }
            self.allocator.free(wheel_data);
        }

        // Install each wheel
        var results = std.ArrayList(InstallResult){};
        errdefer {
            for (results.items) |r| {
                self.allocator.free(r.name);
                self.allocator.free(r.version);
            }
            results.deinit(self.allocator);
        }

        for (pypi_urls.items, 0..) |url, i| {
            const pkg_idx = url_to_pkg.get(url) orelse continue;
            const pkg = packages[pkg_idx];
            const data = wheel_data[i] orelse continue;

            // Verify hash if configured
            if (self.config.verify_hashes) {
                if (pkg.sha256) |expected_hash| {
                    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
                    hasher.update(data);
                    var hash_buf: [64]u8 = undefined;
                    const actual_hash = std.fmt.bytesToHex(hasher.finalResult(), .lower);
                    @memcpy(hash_buf[0..64], &actual_hash);
                    if (!std.mem.eql(u8, hash_buf[0..64], expected_hash)) {
                        continue; // Skip invalid wheel
                    }
                }
            }

            // Extract wheel to site-packages
            const result = try self.extractWheel(data, pkg.name, pkg.version);
            try results.append(self.allocator, result);
        }

        return try results.toOwnedSlice(self.allocator);
    }

    /// Download wheels in parallel using H2 multiplexing
    fn downloadWheelsParallel(self: *Installer, urls: []const []const u8) ![]?[]const u8 {
        if (urls.len == 0) return &[_]?[]const u8{};

        var results = try self.allocator.alloc(?[]const u8, urls.len);
        @memset(results, null);
        errdefer {
            for (results) |r| {
                if (r) |data| self.allocator.free(data);
            }
            self.allocator.free(results);
        }

        // Use H2 Client with getAll for parallel fetching
        var h2_client = h2.Client.init(self.allocator);
        defer h2_client.deinit();

        // Fetch all wheels using full URLs
        const responses = h2_client.getAll(urls) catch |err| {
            std.debug.print("H2 getAll failed: {any}\n", .{err});
            return results;
        };
        defer {
            for (0..responses.len) |j| {
                var r = &responses[j];
                r.deinit();
            }
            self.allocator.free(responses);
        }

        // Copy response bodies to results
        for (responses, 0..) |resp, i| {
            if (resp.status == 200) {
                if (resp.body.len > 0) {
                    results[i] = try self.allocator.dupe(u8, resp.body);
                }
            }
        }

        return results;
    }

    /// Extract wheel ZIP to site-packages
    fn extractWheel(
        self: *Installer,
        wheel_data: []const u8,
        name: []const u8,
        version: []const u8,
    ) !InstallResult {
        // Remove existing package directories if they exist
        // Convert name to filesystem form (e.g., charset-normalizer -> charset_normalizer)
        var fs_name_buf: [256]u8 = undefined;
        var fs_name_len: usize = 0;
        for (name) |c| {
            fs_name_buf[fs_name_len] = if (c == '-') '_' else c;
            fs_name_len += 1;
        }
        const fs_name = fs_name_buf[0..fs_name_len];

        // Remove existing dist-info (e.g., charset_normalizer-3.4.4.dist-info)
        const dist_info_dir = try std.fmt.allocPrint(self.allocator, "{s}/{s}-{s}.dist-info", .{ self.site_packages, fs_name, version });
        defer self.allocator.free(dist_info_dir);
        std.fs.cwd().deleteTree(dist_info_dir) catch {};

        // Remove existing package dir
        const pkg_dir = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.site_packages, fs_name });
        defer self.allocator.free(pkg_dir);
        std.fs.cwd().deleteTree(pkg_dir) catch {};

        // Write wheel to temp file (std.zip requires File.Reader)
        const tmp_path = try std.fmt.allocPrint(self.allocator, "/tmp/metal0-wheel-{s}-{s}.whl", .{ name, version });
        defer self.allocator.free(tmp_path);

        {
            const tmp_file = try std.fs.cwd().createFile(tmp_path, .{});
            defer tmp_file.close();
            try tmp_file.writeAll(wheel_data);
        }
        defer std.fs.cwd().deleteFile(tmp_path) catch {};

        // Open and extract
        const file = try std.fs.cwd().openFile(tmp_path, .{});
        defer file.close();

        var read_buffer: [8192]u8 = undefined;
        var file_reader = file.reader(&read_buffer);

        // Create site-packages dir if needed
        std.fs.cwd().makePath(self.site_packages) catch {};

        var dest_dir = try std.fs.cwd().openDir(self.site_packages, .{});
        defer dest_dir.close();

        // Use std.zip.extract
        std.zip.extract(dest_dir, &file_reader, .{}) catch |err| {
            std.debug.print("ZIP extract failed for {s}: {any}\n", .{ name, err });
            return error.ExtractionFailed;
        };

        return .{
            .name = try self.allocator.dupe(u8, name),
            .version = try self.allocator.dupe(u8, version),
            .files_installed = 1, // TODO: count actual files
            .size_bytes = wheel_data.len,
        };
    }
};

/// Package info for installation
pub const PackageInfo = struct {
    name: []const u8,
    version: []const u8,
    wheel_url: ?[]const u8,
    sha256: ?[]const u8,
};

/// Detect the best site-packages directory
fn detectSitePackages(allocator: std.mem.Allocator) ![]const u8 {
    // Check for virtual environment first
    if (std.posix.getenv("VIRTUAL_ENV")) |venv| {
        const path = try std.fmt.allocPrint(
            allocator,
            "{s}/lib/python3.11/site-packages",
            .{venv},
        );
        if (dirExists(path)) return path;
        allocator.free(path);

        // Try other Python versions
        var version: u8 = 12;
        while (version >= 8) : (version -= 1) {
            const versioned_path = try std.fmt.allocPrint(
                allocator,
                "{s}/lib/python3.{d}/site-packages",
                .{ venv, version },
            );
            if (dirExists(versioned_path)) return versioned_path;
            allocator.free(versioned_path);
        }
    }

    // Check for local .venv
    var version: u8 = 13;
    while (version >= 8) : (version -= 1) {
        const local_venv = try std.fmt.allocPrint(
            allocator,
            ".venv/lib/python3.{d}/site-packages",
            .{version},
        );
        if (dirExists(local_venv)) return local_venv;
        allocator.free(local_venv);
    }

    // macOS Framework Python
    if (builtin.os.tag == .macos) {
        version = 13;
        while (version >= 8) : (version -= 1) {
            const framework = try std.fmt.allocPrint(
                allocator,
                "/Library/Frameworks/Python.framework/Versions/3.{d}/lib/python3.{d}/site-packages",
                .{ version, version },
            );
            if (dirExists(framework)) return framework;
            allocator.free(framework);
        }
    }

    // User site-packages
    if (std.posix.getenv("HOME")) |home| {
        version = 13;
        while (version >= 8) : (version -= 1) {
            const user_path = if (builtin.os.tag == .macos)
                try std.fmt.allocPrint(
                    allocator,
                    "{s}/Library/Python/3.{d}/lib/python/site-packages",
                    .{ home, version },
                )
            else
                try std.fmt.allocPrint(
                    allocator,
                    "{s}/.local/lib/python3.{d}/site-packages",
                    .{ home, version },
                );
            if (dirExists(user_path)) return user_path;
            allocator.free(user_path);
        }
    }

    return error.NoSitePackages;
}

fn dirExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

/// Compare package names normalized (case-insensitive, - == _)
fn normalizedEql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        const na = if (ca == '-') '_' else std.ascii.toLower(ca);
        const nb = if (cb == '-') '_' else std.ascii.toLower(cb);
        if (na != nb) return false;
    }
    return true;
}

// Tests
test "detect site packages" {
    const allocator = std.testing.allocator;
    const path = detectSitePackages(allocator) catch |err| {
        std.debug.print("Site packages detection failed: {any}\n", .{err});
        return;
    };
    defer allocator.free(path);
    try std.testing.expect(path.len > 0);
}
