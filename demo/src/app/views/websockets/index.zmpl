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
        <div
            class="cell"
            jetzig-connect="$.cells.{{index}}"
            jetzig-transform="cell"
            jetzig-click="move"
            id="tic-tac-toe-cell-{{index}}"
            data-cell="{{index}}"
        >
        </div>
    }
</div>

<button id="reset-button">Reset Game</button>

<div id="victor"></div>

<script src="/party.js"></script>
<link rel="stylesheet" href="/party.css" />

<script>
    jetzig.channel.onStateChanged(state => {
        if (!state.victor) {
            const element = document.querySelector("#victor");
            element.style.visibility = 'hidden';
        }
    });

    jetzig.channel.onMessage(message => {
        if (message.err) {
            console.log(message.err);
        }
    });

    jetzig.channel.receive("victor", (data) => {
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

    jetzig.channel.receive("game_over", (data) => {
        const element = document.querySelector("#board");
        element.classList.remove('flash-animation');
        void element.offsetWidth;
        element.classList.add('flash-animation');
    });

    jetzig.channel.transform("cell", (value) => (
        { player: "&#9992;&#65039;", cpu: "&#129422;" }[value] || ""
    ));
    document.querySelectorAll("#board div.cell").forEach(element => {
        element.addEventListener("click", () => {
            jetzig.channel.actions.move(parseInt(element.dataset.cell));
        });
    });

    document.querySelector("#reset-button").addEventListener("click", () => {
        jetzig.channel.actions.reset();
    });

</script>
