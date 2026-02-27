pub const database = .{
    .development = .{
        .adapter = .postgresql,
        .username = "postgres",
        .password = "postgres",
        .hostname = "localhost",
        .database = "jetzig_demo_dev",
        .port = 5432,
    },
    // This configuration is used for CI
    // in GitHub
    .testing = .{
        .adapter = .postgresql,
        .database = "jetzig_demo_test",
    },
};
