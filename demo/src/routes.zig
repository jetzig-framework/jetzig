const jetzig = @import("jetzig");

pub const routes = [_]jetzig.Route{
        .{
            .id = "RGJmKq1nsYnrukQaUGcnAqG3LM69qElM",
            .name = "nested_route_example_get",
            .action = .get,
            .view_name = "nested/route/example",
            .view = jetzig.Route.View{ .with_id = @import("app/views/nested/route/example.zig").get },
            .path = "app/views/nested/route/example.zig",
            .static = false,
            .uri_path = "/nested/route/example",
            .template = "nested/route/example/get",
            .before_callbacks = jetzig.callbacks.beforeCallbacks(@import("app/views/nested/route/example.zig")),
            .after_callbacks = jetzig.callbacks.afterCallbacks(@import("app/views/nested/route/example.zig")),
            .layout = if (@hasDecl(@import("app/views/nested/route/example.zig"), "layout")) @import("app/views/nested/route/example.zig").layout else null,
            .json_params = &[_][]const u8 { "{\"id\":\"foo\",\"params\":{\"foo\":\"bar\"}}", 
"{\"id\":\"foo\"}" },
            .formats = if (@hasDecl(@import("app/views/nested/route/example.zig"), "formats")) @import("app/views/nested/route/example.zig").formats else null,
        },
        .{
            .id = "RQDXM6y9q0VMbtChKtBoTdBKLPDfx33A",
            .name = "static_get",
            .action = .get,
            .view_name = "static",
            .view = jetzig.Route.View{ .legacy_with_id = @import("app/views/static.zig").get },
            .path = "app/views/static.zig",
            .static = false,
            .uri_path = "/static",
            .template = "static/get",
            .before_callbacks = jetzig.callbacks.beforeCallbacks(@import("app/views/static.zig")),
            .after_callbacks = jetzig.callbacks.afterCallbacks(@import("app/views/static.zig")),
            .layout = if (@hasDecl(@import("app/views/static.zig"), "layout")) @import("app/views/static.zig").layout else null,
            .json_params = &[_][]const u8 { "{\"id\":\"123\",\"params\":{\"foo\":\"hi\",\"bar\":\"bye\"}}", 
"{\"id\":\"456\",\"params\":{\"foo\":\"hello\",\"bar\":\"goodbye\"}}" },
            .formats = if (@hasDecl(@import("app/views/static.zig"), "formats")) @import("app/views/static.zig").formats else null,
        },
        .{
            .id = "cIJuzHGbXDXHd0zVrh0tqxSsmXWjfQlE",
            .name = "static_index",
            .action = .index,
            .view_name = "static",
            .view = jetzig.Route.View{ .legacy_without_id = @import("app/views/static.zig").index },
            .path = "app/views/static.zig",
            .static = false,
            .uri_path = "/static",
            .template = "static/index",
            .before_callbacks = jetzig.callbacks.beforeCallbacks(@import("app/views/static.zig")),
            .after_callbacks = jetzig.callbacks.afterCallbacks(@import("app/views/static.zig")),
            .layout = if (@hasDecl(@import("app/views/static.zig"), "layout")) @import("app/views/static.zig").layout else null,
            .json_params = &[_][]const u8 { "{\"params\":{\"foo\":\"hi\",\"bar\":\"bye\"}}", 
"{\"params\":{\"foo\":\"hello\",\"bar\":\"goodbye\"}}" },
            .formats = if (@hasDecl(@import("app/views/static.zig"), "formats")) @import("app/views/static.zig").formats else null,
        },
        .{
            .id = "fuafLMIkCJWCy4NuuMM5dgNov4my1D4x",
            .name = "session_edit",
            .action = .edit,
            .view_name = "session",
            .view = jetzig.Route.View{ .with_id = @import("app/views/session.zig").edit },
            .path = "app/views/session.zig",
            .static = false,
            .uri_path = "/session/edit",
            .template = "session/edit",
            .before_callbacks = jetzig.callbacks.beforeCallbacks(@import("app/views/session.zig")),
            .after_callbacks = jetzig.callbacks.afterCallbacks(@import("app/views/session.zig")),
            .layout = if (@hasDecl(@import("app/views/session.zig"), "layout")) @import("app/views/session.zig").layout else null,
            .json_params = &[_][]const u8 {  },
            .formats = if (@hasDecl(@import("app/views/session.zig"), "formats")) @import("app/views/session.zig").formats else null,
        },
        .{
            .id = "GmsGF6AS9G6s2MgpNdDHpo0nP0ea9HF2",
            .name = "root_edit",
            .action = .edit,
            .view_name = "root",
            .view = jetzig.Route.View{ .with_id = @import("app/views/root.zig").edit },
            .path = "app/views/root.zig",
            .static = false,
            .uri_path = "/edit",
            .template = "root/edit",
            .before_callbacks = jetzig.callbacks.beforeCallbacks(@import("app/views/root.zig")),
            .after_callbacks = jetzig.callbacks.afterCallbacks(@import("app/views/root.zig")),
            .layout = if (@hasDecl(@import("app/views/root.zig"), "layout")) @import("app/views/root.zig").layout else null,
            .json_params = &[_][]const u8 {  },
            .formats = if (@hasDecl(@import("app/views/root.zig"), "formats")) @import("app/views/root.zig").formats else null,
        },
        .{
            .id = "tupJPgayfGiMxm01T2wbSqhV5eV1t9Cj",
            .name = "format_get",
            .action = .get,
            .view_name = "format",
            .view = jetzig.Route.View{ .legacy_with_id = @import("app/views/format.zig").get },
            .path = "app/views/format.zig",
            .static = false,
            .uri_path = "/format",
            .template = "format/get",
            .before_callbacks = jetzig.callbacks.beforeCallbacks(@import("app/views/format.zig")),
            .after_callbacks = jetzig.callbacks.afterCallbacks(@import("app/views/format.zig")),
            .layout = if (@hasDecl(@import("app/views/format.zig"), "layout")) @import("app/views/format.zig").layout else null,
            .json_params = &[_][]const u8 {  },
            .formats = if (@hasDecl(@import("app/views/format.zig"), "formats")) @import("app/views/format.zig").formats else null,
        },
        .{
            .id = "TTE41AX5C09LyTILQLIEnZx7fJzVRZbS",
            .name = "quotes_get",
            .action = .get,
            .view_name = "quotes",
            .view = jetzig.Route.View{ .legacy_with_id = @import("app/views/quotes.zig").get },
            .path = "app/views/quotes.zig",
            .static = false,
            .uri_path = "/quotes",
            .template = "quotes/get",
            .before_callbacks = jetzig.callbacks.beforeCallbacks(@import("app/views/quotes.zig")),
            .after_callbacks = jetzig.callbacks.afterCallbacks(@import("app/views/quotes.zig")),
            .layout = if (@hasDecl(@import("app/views/quotes.zig"), "layout")) @import("app/views/quotes.zig").layout else null,
            .json_params = &[_][]const u8 {  },
            .formats = if (@hasDecl(@import("app/views/quotes.zig"), "formats")) @import("app/views/quotes.zig").formats else null,
        },
        .{
            .id = "qcuSLMzQAAYMN64rNV0FVn2vJb7x3d3K",
            .name = "background_jobs_index",
            .action = .index,
            .view_name = "background_jobs",
            .view = jetzig.Route.View{ .legacy_without_id = @import("app/views/background_jobs.zig").index },
            .path = "app/views/background_jobs.zig",
            .static = false,
            .uri_path = "/background_jobs",
            .template = "background_jobs/index",
            .before_callbacks = jetzig.callbacks.beforeCallbacks(@import("app/views/background_jobs.zig")),
            .after_callbacks = jetzig.callbacks.afterCallbacks(@import("app/views/background_jobs.zig")),
            .layout = if (@hasDecl(@import("app/views/background_jobs.zig"), "layout")) @import("app/views/background_jobs.zig").layout else null,
            .json_params = &[_][]const u8 {  },
            .formats = if (@hasDecl(@import("app/views/background_jobs.zig"), "formats")) @import("app/views/background_jobs.zig").formats else null,
        },
        .{
            .id = "fEIpVaQxdC5780a36HbqR7Hq56phPaWl",
            .name = "session_index",
            .action = .index,
            .view_name = "session",
            .view = jetzig.Route.View{ .legacy_without_id = @import("app/views/session.zig").index },
            .path = "app/views/session.zig",
            .static = false,
            .uri_path = "/session",
            .template = "session/index",
            .before_callbacks = jetzig.callbacks.beforeCallbacks(@import("app/views/session.zig")),
            .after_callbacks = jetzig.callbacks.afterCallbacks(@import("app/views/session.zig")),
            .layout = if (@hasDecl(@import("app/views/session.zig"), "layout")) @import("app/views/session.zig").layout else null,
            .json_params = &[_][]const u8 {  },
            .formats = if (@hasDecl(@import("app/views/session.zig"), "formats")) @import("app/views/session.zig").formats else null,
        },
        .{
            .id = "hZYjJ5xSrGCNsqU99TLFpLWjTmuVvuzU",
            .name = "root_index",
            .action = .index,
            .view_name = "root",
            .view = jetzig.Route.View{ .legacy_without_id = @import("app/views/root.zig").index },
            .path = "app/views/root.zig",
            .static = false,
            .uri_path = "/",
            .template = "root/index",
            .before_callbacks = jetzig.callbacks.beforeCallbacks(@import("app/views/root.zig")),
            .after_callbacks = jetzig.callbacks.afterCallbacks(@import("app/views/root.zig")),
            .layout = if (@hasDecl(@import("app/views/root.zig"), "layout")) @import("app/views/root.zig").layout else null,
            .json_params = &[_][]const u8 {  },
            .formats = if (@hasDecl(@import("app/views/root.zig"), "formats")) @import("app/views/root.zig").formats else null,
        },
        .{
            .id = "hlY9sUEftxn1cFagCZ0YG2QWMzStZSHH",
            .name = "redirect_index",
            .action = .index,
            .view_name = "redirect",
            .view = jetzig.Route.View{ .without_id = @import("app/views/redirect.zig").index },
            .path = "app/views/redirect.zig",
            .static = false,
            .uri_path = "/redirect",
            .template = "redirect/index",
            .before_callbacks = jetzig.callbacks.beforeCallbacks(@import("app/views/redirect.zig")),
            .after_callbacks = jetzig.callbacks.afterCallbacks(@import("app/views/redirect.zig")),
            .layout = if (@hasDecl(@import("app/views/redirect.zig"), "layout")) @import("app/views/redirect.zig").layout else null,
            .json_params = &[_][]const u8 {  },
            .formats = if (@hasDecl(@import("app/views/redirect.zig"), "formats")) @import("app/views/redirect.zig").formats else null,
        },
        .{
            .id = "bxMCdSzNla8dOrJIqIFnCGWvxx5J1rbt",
            .name = "format_index",
            .action = .index,
            .view_name = "format",
            .view = jetzig.Route.View{ .legacy_without_id = @import("app/views/format.zig").index },
            .path = "app/views/format.zig",
            .static = false,
            .uri_path = "/format",
            .template = "format/index",
            .before_callbacks = jetzig.callbacks.beforeCallbacks(@import("app/views/format.zig")),
            .after_callbacks = jetzig.callbacks.afterCallbacks(@import("app/views/format.zig")),
            .layout = if (@hasDecl(@import("app/views/format.zig"), "layout")) @import("app/views/format.zig").layout else null,
            .json_params = &[_][]const u8 {  },
            .formats = if (@hasDecl(@import("app/views/format.zig"), "formats")) @import("app/views/format.zig").formats else null,
        },
        .{
            .id = "rIxNbXouG3ZpqHFO8RAhKuG4dfxrCmfU",
            .name = "nested_route_example_index",
            .action = .index,
            .view_name = "nested/route/example",
            .view = jetzig.Route.View{ .without_id = @import("app/views/nested/route/example.zig").index },
            .path = "app/views/nested/route/example.zig",
            .static = false,
            .uri_path = "/nested/route/example",
            .template = "nested/route/example/index",
            .before_callbacks = jetzig.callbacks.beforeCallbacks(@import("app/views/nested/route/example.zig")),
            .after_callbacks = jetzig.callbacks.afterCallbacks(@import("app/views/nested/route/example.zig")),
            .layout = if (@hasDecl(@import("app/views/nested/route/example.zig"), "layout")) @import("app/views/nested/route/example.zig").layout else null,
            .json_params = &[_][]const u8 {  },
            .formats = if (@hasDecl(@import("app/views/nested/route/example.zig"), "formats")) @import("app/views/nested/route/example.zig").formats else null,
        },
        .{
            .id = "MDYdlPqfJvJHMzcioZUZdK2TOnx7i8t3",
            .name = "mail_index",
            .action = .index,
            .view_name = "mail",
            .view = jetzig.Route.View{ .legacy_without_id = @import("app/views/mail.zig").index },
            .path = "app/views/mail.zig",
            .static = false,
            .uri_path = "/mail",
            .template = "mail/index",
            .before_callbacks = jetzig.callbacks.beforeCallbacks(@import("app/views/mail.zig")),
            .after_callbacks = jetzig.callbacks.afterCallbacks(@import("app/views/mail.zig")),
            .layout = if (@hasDecl(@import("app/views/mail.zig"), "layout")) @import("app/views/mail.zig").layout else null,
            .json_params = &[_][]const u8 {  },
            .formats = if (@hasDecl(@import("app/views/mail.zig"), "formats")) @import("app/views/mail.zig").formats else null,
        },
        .{
            .id = "JVZVGMPWkYQzwVvzU2GyNyliLXjmXp3c",
            .name = "anti_csrf_index",
            .action = .index,
            .view_name = "anti_csrf",
            .view = jetzig.Route.View{ .without_id = @import("app/views/anti_csrf.zig").index },
            .path = "app/views/anti_csrf.zig",
            .static = false,
            .uri_path = "/anti_csrf",
            .template = "anti_csrf/index",
            .before_callbacks = jetzig.callbacks.beforeCallbacks(@import("app/views/anti_csrf.zig")),
            .after_callbacks = jetzig.callbacks.afterCallbacks(@import("app/views/anti_csrf.zig")),
            .layout = if (@hasDecl(@import("app/views/anti_csrf.zig"), "layout")) @import("app/views/anti_csrf.zig").layout else null,
            .json_params = &[_][]const u8 {  },
            .formats = if (@hasDecl(@import("app/views/anti_csrf.zig"), "formats")) @import("app/views/anti_csrf.zig").formats else null,
        },
        .{
            .id = "WxnEz7xrSDSwdw95SwtH3p1pilaroxnr",
            .name = "markdown_index",
            .action = .index,
            .view_name = "markdown",
            .view = jetzig.Route.View{ .legacy_without_id = @import("app/views/markdown.zig").index },
            .path = "app/views/markdown.zig",
            .static = false,
            .uri_path = "/markdown",
            .template = "markdown/index",
            .before_callbacks = jetzig.callbacks.beforeCallbacks(@import("app/views/markdown.zig")),
            .after_callbacks = jetzig.callbacks.afterCallbacks(@import("app/views/markdown.zig")),
            .layout = if (@hasDecl(@import("app/views/markdown.zig"), "layout")) @import("app/views/markdown.zig").layout else null,
            .json_params = &[_][]const u8 {  },
            .formats = if (@hasDecl(@import("app/views/markdown.zig"), "formats")) @import("app/views/markdown.zig").formats else null,
        },
        .{
            .id = "LNFRaT4tqJrf1f11TJXyzmkfZtITVvqd",
            .name = "init_index",
            .action = .index,
            .view_name = "init",
            .view = jetzig.Route.View{ .legacy_without_id = @import("app/views/init.zig").index },
            .path = "app/views/init.zig",
            .static = false,
            .uri_path = "/init",
            .template = "init/index",
            .before_callbacks = jetzig.callbacks.beforeCallbacks(@import("app/views/init.zig")),
            .after_callbacks = jetzig.callbacks.afterCallbacks(@import("app/views/init.zig")),
            .layout = if (@hasDecl(@import("app/views/init.zig"), "layout")) @import("app/views/init.zig").layout else null,
            .json_params = &[_][]const u8 {  },
            .formats = if (@hasDecl(@import("app/views/init.zig"), "formats")) @import("app/views/init.zig").formats else null,
        },
        .{
            .id = "xRO7XerJH97skZvolf7A6XoAUKW6NypE",
            .name = "kvstore_index",
            .action = .index,
            .view_name = "kvstore",
            .view = jetzig.Route.View{ .without_id = @import("app/views/kvstore.zig").index },
            .path = "app/views/kvstore.zig",
            .static = false,
            .uri_path = "/kvstore",
            .template = "kvstore/index",
            .before_callbacks = jetzig.callbacks.beforeCallbacks(@import("app/views/kvstore.zig")),
            .after_callbacks = jetzig.callbacks.afterCallbacks(@import("app/views/kvstore.zig")),
            .layout = if (@hasDecl(@import("app/views/kvstore.zig"), "layout")) @import("app/views/kvstore.zig").layout else null,
            .json_params = &[_][]const u8 {  },
            .formats = if (@hasDecl(@import("app/views/kvstore.zig"), "formats")) @import("app/views/kvstore.zig").formats else null,
        },
        .{
            .id = "OZXcPZfi428ON34mmPs6rveiTyYZZk7r",
            .name = "render_template_index",
            .action = .index,
            .view_name = "render_template",
            .view = jetzig.Route.View{ .without_id = @import("app/views/render_template.zig").index },
            .path = "app/views/render_template.zig",
            .static = false,
            .uri_path = "/render_template",
            .template = "render_template/index",
            .before_callbacks = jetzig.callbacks.beforeCallbacks(@import("app/views/render_template.zig")),
            .after_callbacks = jetzig.callbacks.afterCallbacks(@import("app/views/render_template.zig")),
            .layout = if (@hasDecl(@import("app/views/render_template.zig"), "layout")) @import("app/views/render_template.zig").layout else null,
            .json_params = &[_][]const u8 {  },
            .formats = if (@hasDecl(@import("app/views/render_template.zig"), "formats")) @import("app/views/render_template.zig").formats else null,
        },
        .{
            .id = "PqEitHYDIGmhdGNJY1duijJ88GlmxC57",
            .name = "cache_index",
            .action = .index,
            .view_name = "cache",
            .view = jetzig.Route.View{ .legacy_without_id = @import("app/views/cache.zig").index },
            .path = "app/views/cache.zig",
            .static = false,
            .uri_path = "/cache",
            .template = "cache/index",
            .before_callbacks = jetzig.callbacks.beforeCallbacks(@import("app/views/cache.zig")),
            .after_callbacks = jetzig.callbacks.afterCallbacks(@import("app/views/cache.zig")),
            .layout = if (@hasDecl(@import("app/views/cache.zig"), "layout")) @import("app/views/cache.zig").layout else null,
            .json_params = &[_][]const u8 {  },
            .formats = if (@hasDecl(@import("app/views/cache.zig"), "formats")) @import("app/views/cache.zig").formats else null,
        },
        .{
            .id = "PAmbq36hsUlpA9FE5wnq4KWQCFtRmXAm",
            .name = "basic_index",
            .action = .index,
            .view_name = "basic",
            .view = jetzig.Route.View{ .legacy_without_id = @import("app/views/basic.zig").index },
            .path = "app/views/basic.zig",
            .static = false,
            .uri_path = "/basic",
            .template = "basic/index",
            .before_callbacks = jetzig.callbacks.beforeCallbacks(@import("app/views/basic.zig")),
            .after_callbacks = jetzig.callbacks.afterCallbacks(@import("app/views/basic.zig")),
            .layout = if (@hasDecl(@import("app/views/basic.zig"), "layout")) @import("app/views/basic.zig").layout else null,
            .json_params = &[_][]const u8 {  },
            .formats = if (@hasDecl(@import("app/views/basic.zig"), "formats")) @import("app/views/basic.zig").formats else null,
        },
        .{
            .id = "XvL4PkpzKXoVQEuOXvzixsov6HX6sQom",
            .name = "errors_index",
            .action = .index,
            .view_name = "errors",
            .view = jetzig.Route.View{ .legacy_without_id = @import("app/views/errors.zig").index },
            .path = "app/views/errors.zig",
            .static = false,
            .uri_path = "/errors",
            .template = "errors/index",
            .before_callbacks = jetzig.callbacks.beforeCallbacks(@import("app/views/errors.zig")),
            .after_callbacks = jetzig.callbacks.afterCallbacks(@import("app/views/errors.zig")),
            .layout = if (@hasDecl(@import("app/views/errors.zig"), "layout")) @import("app/views/errors.zig").layout else null,
            .json_params = &[_][]const u8 {  },
            .formats = if (@hasDecl(@import("app/views/errors.zig"), "formats")) @import("app/views/errors.zig").formats else null,
        },
        .{
            .id = "eUOCJMQ5ZoBwTp5pFJUFVr2laenWUlVn",
            .name = "file_upload_index",
            .action = .index,
            .view_name = "file_upload",
            .view = jetzig.Route.View{ .without_id = @import("app/views/file_upload.zig").index },
            .path = "app/views/file_upload.zig",
            .static = false,
            .uri_path = "/file_upload",
            .template = "file_upload/index",
            .before_callbacks = jetzig.callbacks.beforeCallbacks(@import("app/views/file_upload.zig")),
            .after_callbacks = jetzig.callbacks.afterCallbacks(@import("app/views/file_upload.zig")),
            .layout = if (@hasDecl(@import("app/views/file_upload.zig"), "layout")) @import("app/views/file_upload.zig").layout else null,
            .json_params = &[_][]const u8 {  },
            .formats = if (@hasDecl(@import("app/views/file_upload.zig"), "formats")) @import("app/views/file_upload.zig").formats else null,
        },
        .{
            .id = "vMS9iOity7uJCLa8HUv3WFKV2jW9RDzw",
            .name = "quotes_post",
            .action = .post,
            .view_name = "quotes",
            .view = jetzig.Route.View{ .legacy_without_id = @import("app/views/quotes.zig").post },
            .path = "app/views/quotes.zig",
            .static = false,
            .uri_path = "/quotes",
            .template = "quotes/post",
            .before_callbacks = jetzig.callbacks.beforeCallbacks(@import("app/views/quotes.zig")),
            .after_callbacks = jetzig.callbacks.afterCallbacks(@import("app/views/quotes.zig")),
            .layout = if (@hasDecl(@import("app/views/quotes.zig"), "layout")) @import("app/views/quotes.zig").layout else null,
            .json_params = &[_][]const u8 {  },
            .formats = if (@hasDecl(@import("app/views/quotes.zig"), "formats")) @import("app/views/quotes.zig").formats else null,
        },
        .{
            .id = "ZkOxo7cpVDX5J47H2e3EpDCDv41ki5In",
            .name = "anti_csrf_post",
            .action = .post,
            .view_name = "anti_csrf",
            .view = jetzig.Route.View{ .without_id = @import("app/views/anti_csrf.zig").post },
            .path = "app/views/anti_csrf.zig",
            .static = false,
            .uri_path = "/anti_csrf",
            .template = "anti_csrf/post",
            .before_callbacks = jetzig.callbacks.beforeCallbacks(@import("app/views/anti_csrf.zig")),
            .after_callbacks = jetzig.callbacks.afterCallbacks(@import("app/views/anti_csrf.zig")),
            .layout = if (@hasDecl(@import("app/views/anti_csrf.zig"), "layout")) @import("app/views/anti_csrf.zig").layout else null,
            .json_params = &[_][]const u8 {  },
            .formats = if (@hasDecl(@import("app/views/anti_csrf.zig"), "formats")) @import("app/views/anti_csrf.zig").formats else null,
        },
        .{
            .id = "ESA0VfqrKTR6AtD8x27ITjOQj16XoyJI",
            .name = "session_post",
            .action = .post,
            .view_name = "session",
            .view = jetzig.Route.View{ .legacy_without_id = @import("app/views/session.zig").post },
            .path = "app/views/session.zig",
            .static = false,
            .uri_path = "/session",
            .template = "session/post",
            .before_callbacks = jetzig.callbacks.beforeCallbacks(@import("app/views/session.zig")),
            .after_callbacks = jetzig.callbacks.afterCallbacks(@import("app/views/session.zig")),
            .layout = if (@hasDecl(@import("app/views/session.zig"), "layout")) @import("app/views/session.zig").layout else null,
            .json_params = &[_][]const u8 {  },
            .formats = if (@hasDecl(@import("app/views/session.zig"), "formats")) @import("app/views/session.zig").formats else null,
        },
        .{
            .id = "zmM4FLftB41eoVKtz9LGD5C4CCc0FrBS",
            .name = "cache_post",
            .action = .post,
            .view_name = "cache",
            .view = jetzig.Route.View{ .legacy_without_id = @import("app/views/cache.zig").post },
            .path = "app/views/cache.zig",
            .static = false,
            .uri_path = "/cache",
            .template = "cache/post",
            .before_callbacks = jetzig.callbacks.beforeCallbacks(@import("app/views/cache.zig")),
            .after_callbacks = jetzig.callbacks.afterCallbacks(@import("app/views/cache.zig")),
            .layout = if (@hasDecl(@import("app/views/cache.zig"), "layout")) @import("app/views/cache.zig").layout else null,
            .json_params = &[_][]const u8 {  },
            .formats = if (@hasDecl(@import("app/views/cache.zig"), "formats")) @import("app/views/cache.zig").formats else null,
        },
        .{
            .id = "pXsvArTaNZrKNdoBOrl0FeL4LuwSVCCl",
            .name = "params_post",
            .action = .post,
            .view_name = "params",
            .view = jetzig.Route.View{ .without_id = @import("app/views/params.zig").post },
            .path = "app/views/params.zig",
            .static = false,
            .uri_path = "/params",
            .template = "params/post",
            .before_callbacks = jetzig.callbacks.beforeCallbacks(@import("app/views/params.zig")),
            .after_callbacks = jetzig.callbacks.afterCallbacks(@import("app/views/params.zig")),
            .layout = if (@hasDecl(@import("app/views/params.zig"), "layout")) @import("app/views/params.zig").layout else null,
            .json_params = &[_][]const u8 {  },
            .formats = if (@hasDecl(@import("app/views/params.zig"), "formats")) @import("app/views/params.zig").formats else null,
        },
        .{
            .id = "pHqpr0GKxaiBP8VIpO8TJx0DQHIkulnX",
            .name = "file_upload_post",
            .action = .post,
            .view_name = "file_upload",
            .view = jetzig.Route.View{ .without_id = @import("app/views/file_upload.zig").post },
            .path = "app/views/file_upload.zig",
            .static = false,
            .uri_path = "/file_upload",
            .template = "file_upload/post",
            .before_callbacks = jetzig.callbacks.beforeCallbacks(@import("app/views/file_upload.zig")),
            .after_callbacks = jetzig.callbacks.afterCallbacks(@import("app/views/file_upload.zig")),
            .layout = if (@hasDecl(@import("app/views/file_upload.zig"), "layout")) @import("app/views/file_upload.zig").layout else null,
            .json_params = &[_][]const u8 {  },
            .formats = if (@hasDecl(@import("app/views/file_upload.zig"), "formats")) @import("app/views/file_upload.zig").formats else null,
        },
};

pub const mailers = [_]jetzig.MailerDefinition{
    .{
        .name = "welcome",
        .deliverFn = @import("app/mailers/welcome.zig").deliver,
        .defaults = if (@hasDecl(@import("app/mailers/welcome.zig"), "defaults")) @import("app/mailers/welcome.zig").defaults else null,
        .html_template = "welcome/html",
        .text_template = "welcome/text",
    },
};

pub const jobs = [_]jetzig.JobDefinition{
    .{ .name = "__jetzig_mail", .runFn = jetzig.mail.Job.run },
    .{
        .name = "example",
        .runFn = @import("app/jobs/example.zig").run,
    },
};
test {
    _ = @import("app/views/nested/route/example.zig");
    _ = @import("app/views/static.zig");
    _ = @import("app/views/static.zig");
    _ = @import("app/views/session.zig");
    _ = @import("app/views/root.zig");
    _ = @import("app/views/format.zig");
    _ = @import("app/views/quotes.zig");
    _ = @import("app/views/background_jobs.zig");
    _ = @import("app/views/session.zig");
    _ = @import("app/views/root.zig");
    _ = @import("app/views/redirect.zig");
    _ = @import("app/views/format.zig");
    _ = @import("app/views/nested/route/example.zig");
    _ = @import("app/views/mail.zig");
    _ = @import("app/views/anti_csrf.zig");
    _ = @import("app/views/markdown.zig");
    _ = @import("app/views/init.zig");
    _ = @import("app/views/kvstore.zig");
    _ = @import("app/views/render_template.zig");
    _ = @import("app/views/cache.zig");
    _ = @import("app/views/basic.zig");
    _ = @import("app/views/errors.zig");
    _ = @import("app/views/file_upload.zig");
    _ = @import("app/views/quotes.zig");
    _ = @import("app/views/anti_csrf.zig");
    _ = @import("app/views/session.zig");
    _ = @import("app/views/cache.zig");
    _ = @import("app/views/params.zig");
    _ = @import("app/views/file_upload.zig");
    @import("std").testing.refAllDeclsRecursive(@This());
}
