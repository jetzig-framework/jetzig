<script>
    const channel = {
        websocket: null,
        actions: {},
        stateChangedCallbacks: [],
        messageCallbacks: [],
        onStateChanged: function(callback) { this.stateChangedCallbacks.push(callback); },
        onMessage: function(callback) { this.messageCallbacks.push(callback); },
        publish: function(data) {
            if (this.websocket) {
                const json = JSON.stringify(data);
                this.websocket.send(json);
            }
        },
    };
</script>

@if (context.request) |request|
    @if (request.headers.get("host")) |host|
        <script>
            channel.websocket = new WebSocket('ws://{{host}}{{request.path.base_path}}');
            channel.websocket.addEventListener("message", (event) => {
                const state_tag = "__jetzig_channel_state__:";
                const actions_tag = "__jetzig_actions__:";

                if (event.data.startsWith(state_tag)) {
                    const state = JSON.parse(event.data.slice(state_tag.length));
                    channel.stateChangedCallbacks.forEach((callback) => {
                        callback(state);
                    });
                } else if (event.data.startsWith(actions_tag)) {
                    const data = JSON.parse(event.data.slice(actions_tag.length));
                    data.actions.forEach(action => {
                        channel.actions[action.name] = (...params) => {
                            if (action.params.length != params.length) {
                                throw new Error(`Invalid params for action '${action.name}'`);
                            }
                            [...action.params].forEach((param, index) => {
                                const map = {
                                    s: "string",
                                    b: "boolean",
                                    i: "number",
                                    f: "number",
                                };
                                if (map[param] !== typeof params[index]) {
                                    throw new Error(`Incorrect argument type for argument ${index} in '${action.name}'. Expected: ${map[param]}, found ${typeof params[index]}`);
                                }
                            });

                            channel.websocket.send(`_invoke:${action.name}:${JSON.stringify(params)}`);
                        };
                    });
                } else {
                    const data = JSON.parse(event.data);
                    channel.messageCallbacks.forEach((callback) => {
                        callback(data);
                    });
                }

            });
            @// channel.websocket.addEventListener("open", (event) => {
            @//     // TODO
            @//     channel.publish("websockets", {});
            @// });
        </script>
    @end
@end

<div id="results-wrapper">
    <span class="trophy">&#127942;</span>
    <div id="results">
        <div>Player</div>
        <div id="player-wins"></div>
        <div>CPU</div>
        <div id="cpu-wins"></div>
        <div>Tie</div>
        <div id="ties"></div>
    </div>
    <span class="trophy">&#127942;</span>
</div>

<div id="party-container"></div>

<div class="board" id="board">
    <div class="cell" jetzig-connect="$.cells.0" id="tic-tac-toe-cell-0" data-cell="0"></div>
    <div class="cell" jetzig-connect="$.cells.1" id="tic-tac-toe-cell-1" data-cell="1"></div>
    <div class="cell" jetzig-connect="$.cells.2" id="tic-tac-toe-cell-2" data-cell="2"></div>
    <div class="cell" jetzig-connect="$.cells.3" id="tic-tac-toe-cell-3" data-cell="3"></div>
    <div class="cell" jetzig-connect="$.cells.4" id="tic-tac-toe-cell-4" data-cell="4"></div>
    <div class="cell" jetzig-connect="$.cells.5" id="tic-tac-toe-cell-5" data-cell="5"></div>
    <div class="cell" jetzig-connect="$.cells.6" id="tic-tac-toe-cell-6" data-cell="6"></div>
    <div class="cell" jetzig-connect="$.cells.7" id="tic-tac-toe-cell-7" data-cell="7"></div>
    <div class="cell" jetzig-connect="$.cells.8" id="tic-tac-toe-cell-8" data-cell="8"></div>
</div>

<button id="reset-button">Reset Game</button>


<script src="/party.js"></script>
<link rel="stylesheet" href="/party.css" />

<script>
    channel.onStateChanged(state => {
        console.log(state);
        document.querySelector("#player-wins").innerText = state.results.player;
        document.querySelector("#cpu-wins").innerText = state.results.cpu;
        document.querySelector("#ties").innerText = state.results.ties;

        if (state.winner) {
            triggerPartyAnimation();
        }

        Object.entries(state.cells).forEach(([cell, state]) => {
            const element = document.querySelector(`#tic-tac-toe-cell-${cell}`);
            element.innerHTML = { player: "&#9992;&#65039;", cpu: "&#129422;" }[state] || "";
        });
    });

    channel.onMessage(message => {
        if (message.err) {
            console.log(message.err);
        }
    });

    document.querySelector("#reset-button").addEventListener("click", () => {
        channel.actions.reset();
    });

    document.querySelectorAll("#board div.cell").forEach(element => {
        element.addEventListener("click", () => {
            channel.publish({ cell: parseInt(element.dataset.cell) });
        });
    });
</script>
