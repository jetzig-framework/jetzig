const std = @import("std");

pub const Mail = @import("mail/Mail.zig");
pub const SMTPConfig = @import("mail/SMTPConfig.zig");
pub const MailParams = @import("mail/MailParams.zig");
pub const Address = MailParams.Address;
pub const DefaultMailParams = MailParams.DefaultMailParams;
pub const components = @import("mail/components.zig");
pub const Job = @import("mail/Job.zig");
pub const MailerDefinition = @import("mail/MailerDefinition.zig");
