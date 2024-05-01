<div>
  <span>Saved message in session: {{.message}}</span>
</div>

<hr/>

<form action="/session" method="POST">
  <input type="text" name="message" placeholder="Enter a message here" />
  <input type="submit" />
</form>
