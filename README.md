# Winner Stays On

A live Elo ladder for winner-stays-on ping pong at uni. Pick a free table, start a session, pick the game length and tap the winner. Every rating updates on every phone that's watching.

## How it works

- There are two tables. Each one runs its own session with its own queue, and shows as free or in use.
- A session ends when you end it, or after 10 minutes without a game. Ratings and results are global, so they carry over to every new session.
- Whoever holds the table stays on until they lose. The loser goes to the back of the queue and the next challenger steps up.
- Before each game you pick first to 3, 5 or 11.
- Ratings work like chess.com. Everyone starts at 1000, and after each game both players move by K × (result − expected). K is 40 for a player's first 10 games and 20 after that.
- Organisers sign in to add players and record games. Everyone else watches live without an account.
- A wrong result can be undone straight away or voided later, and every rating is recalculated from the full game history.

## Stack

- `index.html` holds the whole app in plain HTML, CSS and JavaScript, with no build step.
- [Supabase](https://supabase.com) stores players, games and the table, enforces row-level security, pushes realtime updates and handles magic-link sign-in.
- [Vercel](https://vercel.com) serves the static files.

## Run your own copy

1. Create a Supabase project and run `supabase/schema.sql` in the SQL editor.
2. Add your organiser email with `insert into public.organisers (email) values ('you@example.com');`
3. Put your project URL and publishable key in `config.js`.
4. In Supabase, open Authentication, then URL Configuration, and set the Site URL to your site's address so sign-in links land back on it.
5. Import the repo into Vercel. There's nothing to build, so the defaults work.

## Security

The publishable key in `config.js` is public by design. Row-level security decides who can write. Anyone can read players, games and the table, and only signed-in users whose email is in `public.organisers` can add, change or remove anything.

## Next up

- Players register themselves with their email and student number
- Results count only once both players confirm them
