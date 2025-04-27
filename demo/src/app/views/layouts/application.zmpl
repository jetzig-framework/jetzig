<!DOCTYPE html>
<html>
  <head>
    <script src="https://unpkg.com/htmx.org@1.9.10"></script>

    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <script src="https://cdn.tailwindcss.com"></script>
    <link rel="stylesheet" href="/prism.css" />
    {{context.middleware.renderHeader()}}
  </head>

  <body>
    <main>{{zmpl.content}}</main>
    <script src="/prism.js"></script>
    {{context.middleware.renderFooter()}}
  </body>
</html>
