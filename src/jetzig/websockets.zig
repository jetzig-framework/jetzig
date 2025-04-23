pub const RoutedWebsocket = @import("websockets/Websocket.zig").RoutedWebsocket;
pub const Websocket = RoutedWebsocket(@import("root").routes);
pub const Context = @import("websockets/Websocket.zig").Context;
