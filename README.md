# Phoenix2FA

Simple 2FA for Phoenix, built on top of the Phoenix generated authentication system.
- Uses [Wax](https://hexdocs.pm/wax_/readme.html) for Fido2/U2f/WebAthn
- Uses [NimbleTOTP]() for TOTP
- Generated recovery codes randomly using [`:crypto.strong_rand_bytes/1`](https://www.erlang.org/doc/man/crypto.html#strong_rand_bytes-1)


## Database 

```mermaid
classDiagram
direction LR
users "1" --> "*" user_keys
class user_keys {
   string : cred_id
   string : label
   utc_datetime : last_used
   binary : mfa_key
   enum : kind (u2f, totp, recovery)
   fk : user_id
   utc_datetime : inserted_at
   utc_datetime : updated_at
   int : id
}
class users {
   string : email
   string : hashed_password
   utc_datetime : confirmed_at
   utc_datetime : inserted_at
   utc_datetime : updated_at
   int : id
}
```


## Setup

  * Run `mix setup` to install and setup dependencies
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.
