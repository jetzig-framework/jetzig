<html>
  <head>
    <script src="https://unpkg.com/htmx.org@1.9.10"></script>

    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <script src="https://cdn.tailwindcss.com"></script>
  </head>

  <body>
    <div class="text-center pt-10 m-auto">
      <div><img class="p-3 mx-auto" src="/jetzig.png" /></div>

      <div>
        <h1 class="text-3xl text-center p-3 pb-6 font-bold">{.message}</h1>
      </div>

      <button hx-get="/quotes/random" hx-trigger="click" hx-target="#quote" class="bg-[#39b54a] text-white font-bold py-2 px-4 rounded">Click Me</button>

      <div id="quote" class="p-7 mx-auto w-1/2">
        <div hx-get="/quotes/init" hx-trigger="load"></div>
      </div>

      <div>Take a look at the <span class="font-mono">src/app/</span> directory to see how this application works.</div>
      <div>Visit <a class="font-bold text-[#39b54a]" href="https://jetzig.dev/">jetzig.dev</a> to get started.</div>
    </div>
  </body>
</html>
