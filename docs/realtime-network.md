# Experimental node network

QuakeNet's current network step uses a Supabase Realtime Broadcast channel.
It sends only a compact `SeismicTrigger` when the local STA/LTA detector enters
the triggered state:

- anonymous, session-scoped node ID;
- UTC timestamp;
- filtered acceleration peak;
- STA/LTA ratio and algorithm name.

It does not send raw accelerometer samples, device identifiers, account data,
or location. A received trigger is a movement candidate, not earthquake
confirmation and never produces a public alert.

## Run with Realtime enabled

Do not add Supabase credentials to source files. Pass the public project URL
and anon key at build/run time instead:

```powershell
flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

Without both values the app still runs, but node networking is disabled.

## Project configuration

Enable Supabase Realtime Broadcast for the project before testing with two
physical devices. The prototype uses the public channel
`quakenet:movement-candidates:v1`; therefore it is intended only for controlled
development tests. Before distributing any build, replace it with a private
channel and authorization policies, and introduce server-side rate limiting and
multi-node correlation.
