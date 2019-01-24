# Lizard Brain

A computer assisted brain stem.

# Configuration

Configuration is managed entirely by environment variables.  The list of
configuration fields are as follows:

## `DROPBOX_ACCESS_TOKEN`

OAuth 2 Access Token for reading from and wriitng to Dropbox.

## `PUSHOVER_USER`

The user token to send pushover messages to

## `PUSHOVER_API`

The api token to use when sending pushover messages

## `LB_PASS`

The crypt formatted password that (at least) Twilio will use when authentication
with Lizard Brain.

## `LB_NOTES`

Location of [VOTL](https://github.com/vimoutliner/vimoutliner) file used for
inspiration etc.  Some location in dropbox (like `/foo/bar.otl`)

## `LB_NOTES_PASS`

The crypt formatted password that is for the scant www interface Lizard Brain
has.  Should be a hash of `u$username:p$password`.

## `MY_CELL`

The [E.164](https://en.wikipedia.org/wiki/E.164) cell that is authorized
to interact with the Lizard Brain via Twilio.

## `LB_GH_SECRET`

The secret to use for Github authentication.  Maybe just use `LB_PASS` for this?

## `LB_TASKS`

The directory where tasks are located.  Default is `./tasks`.

## twitter

 * `TWITTER_CONSUMER_KEY`
 * `TWITTER_CONSUMER_SECRET`
 * `TWITTER_ACCESS_TOKEN`
 * `TWITTER_ACCESS_TOKEN_SECRET`
