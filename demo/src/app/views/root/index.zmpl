<html>
  <head>
    <script src="https://unpkg.com/htmx.org@1.9.10"></script>

    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <script src="https://cdn.tailwindcss.com"></script>
  </head>

  <body>
    <div class="text-center pt-10 m-auto">
      <div><img class="p-3 mx-auto" src="/jetzig.png" /></div>

      // Renders `src/app/views/root/_quotes.zmpl`:
      <div>{^root/quotes}</div>

      <div>
        <a href="https://github.com/jetzig-framework/zmpl">
          <img class="p-3 m-3 mx-auto" src="/zmpl.png" />
        </a>
      </div>

      <div>Take a look at the <span class="font-mono">/demo/src/app/</span> directory to see how this application works.</div>
      <div>Visit <a class="font-bold text-[#39b54a]" href="https://jetzig.dev/">jetzig.dev</a> to get started.</div>
    </div>
  </body>
</html>
