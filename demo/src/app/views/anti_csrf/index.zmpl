<form action="/anti_csrf" method="POST">
    {{context.authenticityFormElement()}}

    <label>Enter spam here:</label>
    <input type="text" name="spam" />

    <input type="submit" value="Submit Spam" />
</form>

<div>Try clearing `_jetzig_session` cookie before clicking "Submit Spam"</div>
