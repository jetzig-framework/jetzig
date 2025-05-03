<link rel="stylesheet" href="/party.css" />

<div id="party-container"></div>

<jetzig-scope name="game">
    <div id="results-wrapper">
        <span class="trophy">&#127942;</span>
        <div id="results">
            <div>Player</div>
            <div id="player-wins" jetzig-scope="game" jetzig-connect="$.results.player"></div>
            <div>CPU</div>
            <div id="cpu-wins" jetzig-scope="game" jetzig-connect="$.results.cpu"></div>
            <div>Tie</div>
            <div id="ties" jetzig-scope="game" jetzig-connect="$.results.tie"></div>
        </div>
        <span class="trophy">&#127942;</span>
    </div>

    <div class="board" id="board">
        @for (0..9) |index| {
            <div
                class="cell"
                jetzig-connect="$.cells.{{index}}"
                jetzig-transform="{ player: '&#9992;&#65039;', cpu: '&#129422;', tie: '&#129309;' }[value] || ''"
                jetzig-scope="game"
                jetzig-click="move"
                id="tic-tac-toe-cell-{{index}}"
                data-cell="{{index}}"
            >
            </div>
        }
    </div>
</jetzig-scope>


<div id="reset-wrapper">
    <button jetzig-click="reset" id="reset-button">Reset Game</button>
</div>

<div jetzig-style="{ visibility: $.victor === null ? 'hidden' : 'visible' }" id="victor">
    <span>&#127942;</span>
    <span
        jetzig-connect="$.victor"
        jetzig-scope="game"
        jetzig-transform="{ player: '&#9992;&#65039;', cpu: '&#129422;', tie: '&#129309;' }[value] || ''"
    ></span>
    <span>&#127942;</span>
</div>

<script>
    @// Jetzig.channel.onStateChanged((scope, state) => {
    @// });
    @//
    @// Jetzig.channel.onMessage(data => {
    @// });
    @//
    @// Jetzig.channel.receive("victor", data => {
    @//     triggerPartyAnimation();
    @// });
    @//
    @// Jetzig.channel.receive("game_over", data => {
    @//     const element = document.querySelector("#board");
    @//     element.classList.remove('flash-animation');
    @//     void element.offsetWidth;
    @//     element.classList.add('flash-animation');
    @// });
    @//
</script>
