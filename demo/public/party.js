function triggerPartyAnimation() {
    const container = document.getElementById('party-container');
    container.innerHTML = ''; // Clear previous animations

    // Define entities
    const entities = [
        { type: 'dog', emoji: '&#128054;' },
        { type: 'cat', emoji: '&#x1F431;' },
        { type: 'lizard', emoji: '&#129422;' },
        { type: 'jet', emoji: '&#9992;' }
    ];

    // Create random number of each entity (2-5 per type)
    entities.forEach(entity => {
        const count = Math.floor(Math.random() * 4) + 2; // Random 2-5
        for (let i = 0; i < count; i++) {
            const div = document.createElement('div');
            div.className = 'animal';
            div.innerHTML = entity.emoji;
            // Random vertical position (between 20% and 80% of screen height)
            div.style.top = `${20 + Math.random() * 60}%`;
            // Random delay (0 to 1.5s)
            div.style.animationDelay = `${Math.random() * 1.5}s`;
            container.appendChild(div);
            // Trigger animation
            setTimeout(() => {
                div.classList.add(`run-${entity.type}`);
            }, 10);
        }
    });

    // Create confetti (20 pieces)
    for (let i = 0; i < 20; i++) {
        const div = document.createElement('div');
        div.className = 'confetti';
        div.innerHTML = '&#127881;';
        // Random horizontal position
        div.style.left = `${Math.random() * 100}%`;
        // Random delay (0 to 2s)
        div.style.animationDelay = `${Math.random() * 2}s`;
        container.appendChild(div);
        // Trigger fall animation
        setTimeout(() => {
            div.classList.add('fall');
        }, 10);
    }
}
