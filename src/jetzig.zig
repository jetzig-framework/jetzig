const std = @import("std");

pub const zmpl = @import("zmpl").zmpl;
pub const zmd = @import("zmd").zmd;
pub const jetkv = @import("jetkv").jetkv;
pub const jetquery = @import("jetquery");
pub const jetcommon = @import("jetcommon");

pub const http = @import("jetzig/http.zig");
pub const loggers = @import("jetzig/loggers.zig");
pub const data = @import("jetzig/data.zig");
pub const views = @import("jetzig/views.zig");
pub const colors = @import("jetzig/colors.zig");
pub const middleware = @import("jetzig/middleware.zig");
pub const util = @import("jetzig/util.zig");
pub const types = @import("jetzig/types.zig");
pub const markdown = @import("jetzig/markdown.zig");
pub const jobs = @import("jetzig/jobs.zig");
pub const mail = @import("jetzig/mail.zig");
pub const kv = @import("jetzig/kv.zig");
pub const database = @import("jetzig/database.zig");
pub const testing = @import("jetzig/testing.zig");
pub const config = @import("jetzig/config.zig");

pub const DateTime = jetcommon.types.DateTime;
pub const Time = jetcommon.types.Time;
pub const Date = jetcommon.types.Date;

pub const environment = @import("build_options").environment;

/// The primary interface for a Jetzig application. Create an `App` in your application's
/// `src/main.zig` and call `start` to launch the application.
pub const App = @import("jetzig/App.zig");

/// Configuration options for the application server with command-line argument parsing.
pub const Environment = @import("jetzig/Environment.zig");

/// An HTTP request which is passed to (dynamic) view functions and provides access to params,
/// headers, and functions to render a response.
pub const Request = http.Request;

/// A build-time request. Provides a similar interface to a `Request` but outputs are generated
/// when building the application and then returned immediately to the client for matching
/// requests.
pub const StaticRequest = http.StaticRequest;

/// Generic, JSON-compatible data type. Provides `Value` which in turn provides `Object`,
/// `Array`, `String`, `Integer`, `Float`, `Boolean`, and `NullType`.
pub const Data = data.Data;

/// The return value of all view functions. Call `request.render(.ok)` in a view function to
/// generate a `View`.
pub const View = views.View;

/// A route definition. Generated at build type by `Routes.zig`.
pub const Route = views.Route;

/// A middleware route definition. Allows middleware to define custom routes in order to serve
/// content.
pub const MiddlewareRoute = middleware.MiddlewareRoute;

/// An asynchronous job that runs outside of the request/response flow. Create via `Request.job`
/// and set params with `Job.put`, then call `Job.schedule()` to add to the
/// job queue.
pub const Job = jobs.Job;

/// A container for a job definition, includes the job name and run function.
pub const JobDefinition = jobs.Job.JobDefinition;

/// A container for a mailer definition, includes mailer name and mail function.
pub const MailerDefinition = mail.MailerDefinition;

/// A generic logger type. Provides all standard log levels as functions (`INFO`, `WARN`,
/// `ERROR`, etc.). Note that all log functions are CAPITALIZED.
pub const Logger = loggers.Logger;

pub const root = @import("root");
pub const Global = if (@hasDecl(root, "Global")) root.Global else DefaultGlobal;
pub const DefaultGlobal = struct { __jetzig_default: bool };

pub const initHook: ?*const fn (*App) anyerror!void = if (@hasDecl(root, "init")) root.init else null;

/// Initialize a new Jetzig app. Call this from `src/main.zig` and then call
/// `start(@import("routes").routes)` on the returned value.
pub fn init(allocator: std.mem.Allocator) !App {
    const env = try Environment.init(allocator);

    return .{
        .env = env,
        .allocator = allocator,
        .custom_routes = std.ArrayList(views.Route).init(allocator),
        .initHook = initHook,
    };
}
