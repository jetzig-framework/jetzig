<div class="text-center pt-10 m-auto">
  <!-- If present, renders the `message_param` response data value, add `?message=hello` to the
       URL to see the output: -->
  <h2 class="param text-3xl text-[#f7931e]">{{$.message_param}}</h2>

  <!-- Renders `src/app/views/init/_content.zmpl`, passing in the `welcome_message` field from template data. -->
  <div>
    @partial init/content(message: $.welcome_message)
  </div>
</div>
