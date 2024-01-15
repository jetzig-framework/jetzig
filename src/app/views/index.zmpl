<script src="https://unpkg.com/htmx.org@1.9.10"></script>

<div hx-get="/options/latest" hx-trigger="every 1s"></div>

inline for (0..10) |index| {
  <div>
    <button hx-trigger="click" hx-put="/options/{:index}" hx-swap="innerHTML" hx-target="#option">Option #{:index}</option>
  </div>
}

<div id="option">Select an option.</div>
