@args message: *ZmplValue
<div>
  <h1 class="text-3xl text-center p-3 pb-6 font-bold">{{message}}</h1>
</div>

<button hx-get="/quotes/random" hx-trigger="click" hx-target="#quote" class="bg-[#39b54a] text-white font-bold py-2 px-4 rounded">Click Me</button>

<div id="quote" class="p-7 mx-auto w-1/2">
  <div hx-get="/quotes/init" hx-trigger="load"></div>
</div>
