# gcloud-auth

Switch Google Cloud accounts per terminal session, and pick which account each folder uses. Covers both the `gcloud` CLI and Application Default Credentials (ADC). zsh only.

## How it works

`gcloud` keeps its login state, configurations and ADC file in a config directory (`CLOUDSDK_CONFIG`, default `~/.config/gcloud`).
This tool gives each account its own directory under `~/.gcloud-accounts/<name>/` and switches accounts by changing `CLOUDSDK_CONFIG`.

Some client libraries look for ADC only in `~/.config/gcloud` and ignore `CLOUDSDK_CONFIG`, so `GOOGLE_APPLICATION_CREDENTIALS` is also pointed at the account's `application_default_credentials.json`. If you set `GOOGLE_APPLICATION_CREDENTIALS` yourself (for example to a service account key), it is left alone.

```
~/.gcloud-accounts/
├── gcloud-auth.zsh   # the tool
├── personal/         # an account created with add-account (a full gcloud config dir)
│   ├── configurations/
│   ├── application_default_credentials.json
│   └── ...
├── work/             # another account
└── dirs              # folder -> account mapping
```

`~/.config/gcloud` itself is not touched. It is what `gcloud` falls back to when no account is selected.

## Setup

```sh
sh install.sh          # copy into ~/.gcloud-accounts
sh install.sh --link   # symlink to the file in this repo instead (follows updates)
```

`install.sh` does the following:

- creates `~/.gcloud-accounts/`
- places `gcloud-auth.zsh` there
- appends `source ~/.gcloud-accounts/gcloud-auth.zsh` to `.zshrc` (skipped if already present)

Open a new terminal or re-source `.zshrc` afterwards.

## Usage

```
gcloud-auth                      pick an account from a numbered list
gcloud-auth <name>               switch to the given account
gcloud-auth add-account <name> [project-id]
                                 register an account (creates the directory, then logs in to gcloud and ADC via browser)
gcloud-auth add-dir <name>       use the given account in the current folder
gcloud-auth set-project <id>     set the project and ADC quota project of the current account
gcloud-auth status               show the current account
gcloud-auth help                 show help
```

`<name>` is a short label you choose (letters, digits, hyphen, underscore).

### Typical flow

```sh
gcloud-auth add-account personal my-project    # register an account (two browser logins: gcloud, then ADC)
gcloud-auth add-account work work-project
cd ~ && gcloud-auth add-dir personal            # use personal everywhere under your home folder...
cd ~/projects/acme && gcloud-auth add-dir work  # ...except here, where work is used
```

Every account, including ones already logged in under `~/.config/gcloud`, is registered with `add-account`, so you log in once more for each.

## Projects and quota projects

ADC made from a user login needs a quota project, the project that API usage is billed and rate-limited against. Without one, client libraries print a warning and some APIs reject the request.

- `add-account <name> <project-id>` sets the gcloud project before the ADC login, so the same project is recorded as the ADC quota project.
- `set-project <project-id>` changes both for the current account: `gcloud config set project` and `gcloud auth application-default set-quota-project`. Use it instead of `gcloud config set project`, which leaves the ADC quota project unchanged.
- `status` shows the quota project and warns when it is missing or differs from the gcloud project.

Setting a quota project requires the `serviceusage.services.use` permission on that project.

## Switching rules

- **Folder mapping**: on every `cd`, the longest matching entry in `~/.gcloud-accounts/dirs` is applied. This also runs once when the shell starts.
- **No match**: `CLOUDSDK_CONFIG` (and `GOOGLE_APPLICATION_CREDENTIALS`, if this tool set it) is unset and `gcloud` behaves as if this tool were not installed, using `~/.config/gcloud`. To avoid this, map your home folder to an account as shown above.
- **Manual selection**: `gcloud-auth` or `gcloud-auth <name>` pins the account for that terminal, so `cd` no longer changes it. Open a new terminal to go back to folder mapping.
- The current account name is exported as `GCLOUD_AUTH_NAME`, in case you want it in your prompt.

## Mapping file format

`~/.gcloud-accounts/dirs` is tab separated, one `folder<TAB>account` pair per line. `~` expands to `$HOME`. Lines starting with `#` are comments.

```
~	personal
~/projects/acme	work
```

## Notes

- Only the environment of the current shell changes. Processes already running (an IDE, a dev server) keep the account they started with. Restart them after switching.
- Each account directory is a regular gcloud config dir, so you can still use named configurations (`gcloud config configurations ...`) inside an account.
- If you run `gcloud auth application-default login` for an account that had no ADC file yet, run `gcloud-auth <name>` (or `cd .`) afterwards so `GOOGLE_APPLICATION_CREDENTIALS` picks it up.
- Credentials are stored in plain files inside each account directory. Do not put `~/.gcloud-accounts/` in a synced folder or under version control.

## License

MIT. See [LICENSE](LICENSE).
