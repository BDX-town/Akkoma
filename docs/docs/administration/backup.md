# Backup/Restore/Move/Remove your instance

## Backup

1. Stop the Akkoma service.
2. Go to the working directory of Akkoma (default is `/opt/akkoma`)
3. Run `sudo -Hu postgres pg_dump -d akkoma --format=custom -f </path/to/backup_location/akkoma.pgdump>`[¹] (make sure the postgres user has write access to the destination file)
4. Copy `akkoma.pgdump`, `config/config.exs`[²], `uploads` folder, and [static directory](../configuration/static_dir.md) to your backup destination. If you have other modifications, copy those changes too.
5. Restart the Akkoma service.

[¹]: We assume the database name is "akkoma". If not, you can find the correct name in your configuration files.  
[²]: If you have a from source installation, you need `config/prod.secret.exs` instead of `config/config.exs`. The `config/config.exs` file also exists, but in case of from source installations, it only contains the default values and it is tracked by Git, so you don't need to back it up.  

## Restore/Move

1. Optionally reinstall Akkoma (either on the same server or on another server if you want to move servers).
2. Stop the Akkoma service.
3. Go to the working directory of Akkoma (default is `/opt/akkoma`)
4. Copy the above mentioned files back to their original position.
5. Drop the existing database and user[¹]. `sudo -Hu postgres psql -c 'DROP DATABASE akkoma;';` `sudo -Hu postgres psql -c 'DROP USER akkoma;'`
6. Restore the database schema and akkoma role[¹] (replace the password with the one you find in the configuration file), `sudo -Hu postgres psql -c "CREATE USER akkoma WITH ENCRYPTED PASSWORD '<database-password-wich-you-can-find-in-your-configuration-file>';"` `sudo -Hu postgres psql -c "CREATE DATABASE akkoma OWNER akkoma;"`.
7. Now restore the Akkoma instance's data into the empty database schema[¹]: `sudo -Hu postgres pg_restore -d akkoma -v -1 </path/to/backup_location/akkoma.pgdump>`
8. If you installed a newer Akkoma version, you should run the database migrations `./bin/pleroma_ctl migrate`[²].
9. Restart the Akkoma service.
10. Run `sudo -Hu postgres vacuumdb --all --analyze-in-stages`. This will quickly generate the statistics so that postgres can properly plan queries.
11. If setting up on a new server, configure Nginx by using the `installation/nginx/akkoma.nginx` configuration sample or reference the Akkoma installation guide which contains the Nginx configuration instructions.

[¹]: We assume the database name and user are both "akkoma". If not, you can find the correct name in your configuration files.  
[²]: If you have a from source installation, the command is `MIX_ENV=prod mix ecto.migrate`. Note that we prefix with `MIX_ENV=prod` to use the `config/prod.secret.exs` configuration file.  

## Remove

1. Optionally you can remove the users of your instance. This will trigger delete requests for their accounts and posts. Note that this is 'best effort' and doesn't mean that all traces of your instance will be gone from the fediverse.
    * You can do this from the admin-FE where you can select all local users and delete the accounts using the *Moderate multiple users* dropdown.
    * You can also list local users and delete them individually using the CLI tasks for [Managing users](./CLI_tasks/user.md).
2. Stop the Akkoma service `systemctl stop akkoma`
3. Disable Akkoma from systemd `systemctl disable akkoma`
4. Remove the files and folders you created during installation (see installation guide). This includes the akkoma, nginx and systemd files and folders.
5. Reload nginx now that the configuration is removed `systemctl reload nginx`
6. Remove the database and database user[¹] `sudo -Hu postgres psql -c 'DROP DATABASE akkoma;';` `sudo -Hu postgres psql -c 'DROP USER akkoma;'`
7. Remove the system user `userdel akkoma`
8. Remove the dependencies that you don't need anymore (see installation guide). Make sure you don't remove packages that are still needed for other software that you have running!

[¹]: We assume the database name and user are both "akkoma". If not, you can find the correct name in your config files.  

## Docker installations

If running behind Docker, it is required to run the above commands inside of a running database container.  

### Example
Running `docker compose run --rm db pg_dump <...>` will fail and return:
```
pg_dump: error: connection to server on socket "/run/postgresql/.s.PGSQL.5432" failed: No such file or directory 
Is the server running locally and accepting connections on that socket?"
```
However, first starting just the database container with `docker compose up db -d`, and then running `docker compose exec db pg_dump -d akkoma --format=custom -f </your/backup/dir/akkoma.pgdump>` will successfully generate a database dump.  
Then to make the file accessible on the host system you can run `docker compose cp db:</your/backup/dir/akkoma.pgdump> </your/target/location>` to copy if from the container.
