//! CPython source: Lib/sched.py
//!
//! Provides a general purpose event scheduler.
//!
//! Mirrors: CPython Lib/sched.py

pub const types = @import("sched/types.zig");
pub const Event = types.Event;

pub const scheduler = @import("sched/scheduler.zig");
pub const Scheduler = scheduler.Scheduler;

pub const callback = @import("sched/callback.zig");
pub const CallbackContext = callback.CallbackContext;

pub const simple_scheduler = @import("sched/simple_scheduler.zig");
pub const SimpleScheduler = simple_scheduler.SimpleScheduler;

pub const recurring_event = @import("sched/recurring_event.zig");
pub const RecurringEvent = recurring_event.RecurringEvent;
