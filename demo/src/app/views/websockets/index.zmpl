@if (context.request) |request|
    @if (request.headers.get("host")) |host|
        <script>
            const websocket = new WebSocket('ws://{{host}}');

            console.log(websocket);

            websocket.addEventListener("message", (event) => {
                console.log(event.data);
            });

            websocket.addEventListener("open", (event) => {
                websocket.send("websockets:hello jetzig websocket");
            });
        </script>
    @end
@end
