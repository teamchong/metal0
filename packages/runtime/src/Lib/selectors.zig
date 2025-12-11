//! CPython source: Lib/selectors.py
//!
//! Provides high-level abstractions for I/O multiplexing.
//!
//! Mirrors: CPython Lib/selectors.py

const std = @import("std");

// Re-export all types and functions
pub const types = @import("selectors/types.zig");
pub const base_selector = @import("selectors/base_selector.zig");
pub const select_selector = @import("selectors/select_selector.zig");
pub const poll_selector = @import("selectors/poll_selector.zig");
pub const kqueue_selector = @import("selectors/kqueue_selector.zig");
pub const epoll_selector = @import("selectors/epoll_selector.zig");
pub const default_selector = @import("selectors/default_selector.zig");

// Event flags (from types)
pub const EVENT_READ = types.EVENT_READ;
pub const EVENT_WRITE = types.EVENT_WRITE;

// Core types
pub const SelectorKey = types.SelectorKey;
pub const EventResult = types.EventResult;
pub const BaseSelector = base_selector.BaseSelector;
pub const SelectSelector = select_selector.SelectSelector;
pub const PollSelector = poll_selector.PollSelector;
pub const KqueueSelector = kqueue_selector.KqueueSelector;
pub const EpollSelector = epoll_selector.EpollSelector;
pub const DefaultSelector = default_selector.DefaultSelector;

// Factory function
pub const createSelector = default_selector.createSelector;
