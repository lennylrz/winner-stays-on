# Winner Stays On

A live Elo ladder for winner-stays-on ping pong at uni. Pick a free table, start a session, pick the game length and tap the winner. Every rating updates on every phone that's watching.

## How it works

- There are two tables. Each one runs its own session with its own queue, and shows as free or in use.
- A session ends when you end it, or after 10 minutes without a game. Ratings and results are global, so they carry over to every new session.
- Whoever holds the table stays on until they lose. The loser goes to the back of the queue and the next challenger steps up.
- Before each game you pick first to 3, 5 or 11.
- Ratings work like chess.com. Everyone starts at 1000, and after each game both players move by K × (result − expected). K is 40 for a player's first 10 games and 20 after that.
- Players sign in with their name and student number, no email needed. The first sign-in sets the student number and later ones have to match it. Anyone can watch live without signing in.
- Signed-in players run tables, add players and record games, and can undo a game they recorded for 10 minutes. Only organisers rename, archive, void games and reset someone's sign-in.
- A wrong result can be undone straight away or voided later, and every rating is recalculated from the full game history.

## Stack

- `index.html` holds the whole app in plain HTML, CSS and JavaScript, with no build step.
- [Supabase](https://supabase.com) stores players, games and the table, enforces row-level security, pushes realtime updates and checks sign-ins through a few database functions.
- [Vercel](https://vercel.com) serves the static files.

## Run your own copy

1. Create a Supabase project and run `supabase/schema.sql`, then `supabase/member-sign-in.sql`, in the SQL editor.
2. Add yourself as the first player and organiser with `insert into public.players (id, name) values ('me', 'You'); insert into private.members (player_id, is_organiser) values ('me', true);` Then sign in on the site with that name and your student number.
3. Put your project URL and publishable key in `config.js`.
4. Import the repo into Vercel. There's nothing to build, so the defaults work.

## Security

The publishable key in `config.js` is public by design. Anyone can read players, games and tables, and nobody can write to them directly. Every change goes through a database function that checks the sign-in first. Student numbers are stored as bcrypt hashes, and five wrong tries lock a name for 15 minutes. A student number isn't much of a secret, so this keeps out casual mischief rather than a determined cheat, and undone games stay in the database as a record.

## Next up

- Players register themselves with their email and student number
- Results count only once both players confirm them
