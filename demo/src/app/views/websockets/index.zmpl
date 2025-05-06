<link rel="stylesheet" href="/party.css" />
<script src="/party.js"></script>

<div id="party-container"></div>

@if ($.join_token) |join_token|
    <a href="#" jetzig-click="join" data-join-token="{{join_token}}">Join Game</a>
@end

<jetzig-scope name="game">
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

    <div class="board" id="board">
        @for (0..9) |index| {
            <div
                class="cell"
                jetzig-connect="$.cells.{{index}}"
                jetzig-transform="{ player: '&#9992;&#65039;', cpu: '&#129422;', tie: '&#129309;' }[value] || ''"
                jetzig-click="move"
                id="tic-tac-toe-cell-{{index}}"
                data-cell="{{index}}"
            >
            </div>
        }
    </div>

    <div id="reset-wrapper">
        <button jetzig-click="reset" id="reset-button">Reset Game</button>
    </div>

    <div jetzig-style="{ visibility: $.victor === null ? 'hidden' : 'visible' }" id="victor">
        <span>&#127942;</span>
        <span
            jetzig-connect="$.victor"
            jetzig-transform="{ player: '&#9992;&#65039;', cpu: '&#129422;', tie: '&#129309;' }[value] || ''"
        ></span>
        <span>&#127942;</span>
    </div>

    <h4>Share this link to invite another player</h4>
    <div jetzig-connect="$.__connection_url__"></div>
</jetzig-scope>


<script>
    Jetzig.channel.receive("victor", data => {
        triggerPartyAnimation();
    });
    @// Jetzig.channel.onStateChanged((scope, state) => {
    @// });
    @//
    @// Jetzig.channel.onMessage(data => {
    @// });
    @//
    @//
    @// Jetzig.channel.receive("game_over", data => {
    @//     const element = document.querySelector("#board");
    @//     element.classList.remove('flash-animation');
    @//     void element.offsetWidth;
    @//     element.classList.add('flash-animation');
    @// });
    @//
</script>
