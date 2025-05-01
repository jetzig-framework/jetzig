pub const database = .{
    .development = .{
        .adapter = .postgresql,
        .username = "root",
        .password = "root",
        .hostname = "localhost",
        .database = "jetzig_demo_dev",
        .port = 5432, // See `compose.yml`
    },
    // This configuration is used for CI
    // in GitHub
    .testing = .{
        .adapter = .postgresql,
        .database = "jetzig_demo_test",
    },
};
