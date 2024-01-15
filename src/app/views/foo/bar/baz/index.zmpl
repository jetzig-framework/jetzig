if (std.mem.eql(u8, try zmpl.getValueString("message"), "hello there")) {
  const foo = "foo const";
  const bar = "bar const";

  inline for (1..4) |index| {
    <div>Hello {:foo}!</div>
    <div>Hello {:bar}!</div>
    <div>Hello {:index}!</div>
    <div>Hello {.foo}!</div>
    <div>Hello {.bar}!</div>
  }
} else {
  <div>Unexpected message</div>
}
