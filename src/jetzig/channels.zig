pub const RoutedChannel = @import("channels/Channel.zig").RoutedChannel;
pub const Message = @import("channels/Message.zig");
pub const Route = @import("channels/Route.zig");
pub const ActionRouter = @import("channels/ActionRouter.zig");

// For convenience in channel callback functions implemented by users.
pub const Channel = RoutedChannel(@import("root").routes);
