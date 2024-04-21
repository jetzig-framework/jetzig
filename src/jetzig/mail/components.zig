pub const header =
    "MIME-Version: 1.0\r\n" ++
    "Content-Type: multipart/alternative; boundary=\"=_alternative_{0}\"\r\n";

pub const footer =
    "\r\n.\r\n";

pub const text =
    "--=_alternative_{0}\r\n" ++
    "Content-Type: text/plain; charset=\"UTF-8\"\r\n" ++
    "Content-Transfer-Encoding: quoted-printable\r\n\r\n" ++
    "{1s}\r\n";

pub const html =
    "--=_alternative_{0}\r\n" ++
    "Content-Type: text/html; charset=\"UTF-8\"\r\n" ++
    "Content-Transfer-Encoding: quoted-printable\r\n\r\n" ++
    "{1s}\r\n";
