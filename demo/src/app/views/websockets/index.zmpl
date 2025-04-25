<script>
    const channel = {
        websocket: null,
        actions: {},
        stateChangedCallbacks: [],
        messageCallbacks: [],
        invokeCallbacks: {},
        elementMap: {},
        transformerMap: {},
        transformers: {},
        onStateChanged: function(callback) { this.stateChangedCallbacks.push(callback); },
        onMessage: function(callback) { this.messageCallbacks.push(callback); },
        transform: function(ref, callback) {
            if (Object.hasOwn(this.transformers, ref)) {
                this.transformers[ref].push(callback);
            } else {
                this.transformers[ref] = [callback];
            }
        },
        receive: function(ref, callback) {
            if (Object.hasOwn(this.invokeCallbacks, ref)) {
                this.invokeCallbacks[ref].push(callback);
            } else {
                this.invokeCallbacks[ref] = [callback];
            }
        },
        publish: function(data) {
            if (this.websocket) {
                const json = JSON.stringify(data);
                this.websocket.send(json);
            }
        },
    };

    (() => {

@if (context.request) |request|
    const transform = (value, state, element) => {
        const id = element.getAttribute('jetzig-id');
        const key = id && channel.transformerMap[id];
        const transformers = key && channel.transformers[key];
        if (transformers) {
            return transformers.reduce((acc, val) => val(acc), value);
        } else {
            return value === undefined || value == null ? '' : `${value}`
        }
    };

    @if (request.headers.get("host")) |host|
                channel.websocket = new WebSocket('ws://{{host}}{{request.path.base_path}}');
                channel.websocket.addEventListener("message", (event) => {
                    const state_tag = "__jetzig_channel_state__:";
                    const actions_tag = "__jetzig_actions__:";
                    const event_tag = "__jetzig_event__:";

                    if (event.data.startsWith(state_tag)) {
                        const state = JSON.parse(event.data.slice(state_tag.length));
                        Object.entries(channel.elementMap).forEach(([ref, elements]) => {
                            const value = reduceState(ref, state);
                            elements.forEach(element => element.innerHTML = transform(value, state, element));
                        });
                        channel.stateChangedCallbacks.forEach((callback) => {
                            callback(state);
                        });
                    } else if (event.data.startsWith(event_tag)) {
                        const data = JSON.parse(event.data.slice(event_tag.length));
                        if (Object.hasOwn(channel.invokeCallbacks, data.method)) {
                            channel.invokeCallbacks[data.method].forEach(callback => {
                                callback(data);
                            });
                        }
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

                const reduceState = (ref, state) => {
                    if (!ref.startsWith('$.')) throw new Error(`Unexpected ref format: ${ref}`);
                    const args = ref.split('.');
                    args.shift();
                    const isNumeric = (string) => [...string].every(char => '0123456789'.includes(char));
                    const isObject = (object) => object && typeof object === 'object';
                    return args.reduce((acc, arg) => {
                        if (isNumeric(arg)) {
                            if (acc && Array.isArray(acc) && acc.length > arg) return acc[parseInt(arg)];
                            return null;
                        } else {
                            if (acc && isObject(acc)) return acc[arg];
                            return null;
                        }
                    }, state);
                };

                window.addEventListener('DOMContentLoaded', () => {
                    document.querySelectorAll('[jetzig-connect]').forEach(element => {
                        const ref = element.getAttribute('jetzig-connect');
                        if (!channel.elementMap[ref]) channel.elementMap[ref] = [];
                        const id = `jetzig-${crypto.randomUUID()}`;
                        element.setAttribute('jetzig-id', id);
                        channel.elementMap[ref].push(element);
                        channel.transformerMap[id] = element.getAttribute('jetzig-transform');
                    });
                });

                @// channel.websocket.addEventListener("open", (event) => {
                @//     // TODO
                @//     channel.publish("websockets", {});
                @// });
    @end
@end

    })();
</script>

<div id="results-wrapper">
    <span class="trophy">&#127942;</span>
    <div id="results">
        <div>Player</div>
        <div id="player-wins" jetzig-connect="$.results.player"></div>
        <div>CPU</div>
        <div id="cpu-wins" jetzig-connect="$.results.cpu"></div>
        <div>Tie</div>
        <div id="ties" jetzig-connect="$.results.tie"></div>
    </div>
    <span class="trophy">&#127942;</span>
</div>

<div id="party-container"></div>

<div class="board" id="board">
    @for (0..9) |index| {
        <div class="cell" jetzig-connect="$.cells.{{index}}" jetzig-transform="cell" id="tic-tac-toe-cell-{{index}}" data-cell="{{index}}"></div>
    }
</div>

<button id="reset-button">Reset Game</button>

<div id="victor"></div>

<script src="/party.js"></script>
<link rel="stylesheet" href="/party.css" />

<script>
    channel.onStateChanged(state => {
        if (!state.victor) {
            const element = document.querySelector("#victor");
            element.style.visibility = 'hidden';
        }
    });

    channel.onMessage(message => {
        if (message.err) {
            console.log(message.err);
        }
    });

    channel.receive("victor", (data) => {
        const element = document.querySelector("#victor");
        const emoji = {
            player: "&#9992;&#65039;",
            cpu: "&#129422;",
            tie: "&#129309;"
        }[data.params.type] || "";
        element.innerHTML = `&#127942; ${emoji} &#127942;`;
        element.style.visibility = 'visible';
        triggerPartyAnimation();
    });

    channel.receive("game_over", (data) => {
        const element = document.querySelector("#board");
        element.classList.remove('flash-animation');
        void element.offsetWidth;
        element.classList.add('flash-animation');
    });

    channel.transform("cell", (value) => (
        { player: "&#9992;&#65039;", cpu: "&#129422;" }[value] || ""
    ));
    document.querySelectorAll("#board div.cell").forEach(element => {
        element.addEventListener("click", () => {
            channel.actions.move(parseInt(element.dataset.cell));
        });
    });

    document.querySelector("#reset-button").addEventListener("click", () => {
        channel.actions.reset();
    });

</script>
