@if ($.user) |user|
    <div>Logged in as {{user.email}}</div>

    <form method="post" id="logout">
        <input type="hidden" name="logout" value="1" />
        <button type="submit" form="logout">Sign Out</button>
    </form>
@else
    <form method="post" id="login">
      <input type="email" name="email" placeholder="name@example.com">
      <label for="email">Email address</label>
      <input type="password" name="password" placeholder="Password">
      <label for="password">Password</label>
      <button type="submit" form="login">Sign in</button>
    </form>
@end
