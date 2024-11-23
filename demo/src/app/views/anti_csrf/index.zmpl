<form action="/anti_csrf" method="POST">
    {{context.authenticityFormElement()}}

    <label>Enter spam here:</label>
    <input type="text" name="spam" />

    <input type="submit" value="Submit Spam" />
</form>
