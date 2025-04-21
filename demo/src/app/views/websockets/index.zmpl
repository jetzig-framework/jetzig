<script>
    const channel = {
        websocket: null,
        callbacks: [],
        onStateChanged: function(callback) { this.callbacks.push(callback); },
        publish: function(path, data) {
            if (this.websocket) {
                const json = JSON.stringify(data);
                this.websocket.send(`${path}:${json}`);
            }
        },
    };
</script>

@if (context.request) |request|
    @if (request.headers.get("host")) |host|
        <script>
            channel.websocket = new WebSocket('ws://{{host}}');
            channel.websocket.addEventListener("message", (event) => {
                const state = JSON.parse(event.data);
                channel.callbacks.forEach((callback) => {
                    callback(state);
                });
            });
            @// channel.websocket.addEventListener("open", (event) => {
            @//     // TODO
            @//     channel.publish("websockets", {});
            @// });
        </script>
    @end
@end

<style>
    #tic-tac-toe-grid td {
        min-width: 5rem;
        width: 5rem;
        height: 5rem;
        border: 1px dotted black;
        font-size: 3rem;
        font-family: monospace;
    }
</style>

<table id="tic-tac-toe-grid">
    <tbody>
        <tr>
            <td id="tic-tac-toe-cell-1" data-cell="1"></td>
            <td id="tic-tac-toe-cell-2" data-cell="2"></td>
            <td id="tic-tac-toe-cell-3" data-cell="3"></td>
        </tr>
        <tr>
            <td id="tic-tac-toe-cell-4" data-cell="4"></td>
            <td id="tic-tac-toe-cell-5" data-cell="5"></td>
            <td id="tic-tac-toe-cell-6" data-cell="6"></td>
        </tr>
        <tr>
            <td id="tic-tac-toe-cell-7" data-cell="7"></td>
            <td id="tic-tac-toe-cell-8" data-cell="8"></td>
            <td id="tic-tac-toe-cell-9" data-cell="9"></td>
        </tr>
    </tbody>
</table>

<script>
    channel.onStateChanged(state => {
        console.log(state);
        Object.entries(state.cells).forEach(([cell, toggle]) => {
            const element = document.querySelector(`#tic-tac-toe-cell-${cell}`);
            element.innerHTML = toggle ? "&#9992;" : "&#129422;"
        });
    });

    document.querySelectorAll("#tic-tac-toe-grid td").forEach(element => {
        element.addEventListener("click", () => {
            channel.publish("websockets", { toggle: element.dataset.cell });
        });
    });
</script>
