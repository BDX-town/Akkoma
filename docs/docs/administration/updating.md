# Updating your instance

You should **always check the [release notes/changelog](https://akkoma.dev/AkkomaGang/akkoma/src/branch/develop/CHANGELOG.md)** in case there are config deprecations, special update steps, etc.

Besides that, doing the following is generally enough:
## Switch to the akkoma user
```sh
# Using sudo
sudo -su akkoma

# Using doas
doas -su akkoma

# Using su
su -s "$SHELL" akkoma
```

## For OTP installations
```sh
# Download latest stable release
./bin/pleroma_ctl update --branch stable

# Stop akkoma
./bin/pleroma stop # or using the system service manager (e.g. systemctl stop akkoma)

# Run database migrations
./bin/pleroma_ctl migrate

# Update frontend(s). See Frontend Configuration doc for more information.
./bin/pleroma_ctl frontend install pleroma-fe --ref stable

# Start akkoma
./bin/pleroma daemon # or using the system service manager (e.g. systemctl start akkoma)
```

If you selected an alternate flavour on installation, 
you _may_ need to specify `--flavour`, in the same way as 
[when installing](../../installation/otp_en#detecting-flavour).

## For from source installations (using git)
Run as the `akkoma` user:

```sh
# Pull in new changes
git pull

# Run with production configuration
export MIX_ENV=prod

# Download and compile dependencies
mix deps.get
mix compile

# Stop akkoma (replace with your system service manager's equivalent if different)
sudo systemctl stop akkoma

# Run database migrations
mix ecto.migrate

# Update frontend(s). See Frontend Configration doc for more information.
mix pleroma.frontend install pleroma-fe --ref stable

# Start akkoma (replace with your system service manager's equivalent if different)
sudo systemctl start akkoma
```
