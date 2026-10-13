# Automated MySQL Backup and Restore Pipeline

A small database administration project that demonstrates how to automate a logical backup of a MySQL database and restore it into a separate MySQL instance on macOS (Apple Silicon / M1).

The project uses Docker Compose to run two independent MySQL 8.0 containers, `mysqldump` to create timestamped SQL backups, a Bash script to orchestrate backup and restore, and `launchd` to schedule the workflow.

> **Educational lab only:** The example credentials are placeholders for local testing. Do not use them in production. The restore script replaces the destination schema, so all existing data in that schema will be deleted before the backup is imported.

## Architecture

```text
                         macOS (Apple Silicon)
                                  |
                         launchd scheduled job
                                  |
                           scripts/respaldo.sh
                                  |
                    +-------------+-------------+
                    |                           |
                    v                           v
          MySQL Production (A)          MySQL Backup (B)
          Docker container              Docker container
          Host port: 3306                Host port: 3307
                    |
                    | mysqldump
                    v
          Timestamped .sql file
          backups/<database>_<timestamp>.sql
                    |
                    | mysql import
                    +---------------------------> MySQL Backup (B)
```

This is a scheduled backup-and-restore workflow, **not** native continuous MySQL replication. The backup database reflects the source database at the time the backup is created.

## Requirements

- macOS on Apple Silicon (M1 or compatible)
- Docker Desktop for Mac
- Docker Compose (included with current Docker Desktop releases)
- A public sample database, such as the official MySQL Sakila sample database
- `launchd` (included with macOS)

## Repository layout

```text
projecto_respaldo/
├── docker-compose.yml
├── scripts/
│   └── respaldo.sh
├── backups/       # Generated SQL backups (not committed)
├── logs/          # Runtime logs (not committed)
├── evidencias/    # Screenshots for the technical report (not committed by default)
├── .gitignore
└── README.md
```

## 1. Start the MySQL containers

From the project directory:

```bash
docker compose up -d
docker ps
```

The example Compose configuration should define two independent services:

- Production: `mysql-produccion`, available on `127.0.0.1:3306`
- Backup: `mysql-respaldo`, available on `127.0.0.1:3307`

Each service should use its own Docker volume for persistent storage.

## 2. Import the Sakila sample database into Production

Download Sakila from the official MySQL documentation:

- https://dev.mysql.com/doc/sakila/en/
- https://dev.mysql.com/doc/index-other.html

Extract the archive and locate `sakila-schema.sql` and `sakila-data.sql`. Follow the import instructions provided with the version you downloaded. For the example workflow in this repository, the source schema is named `sakila`.

After importing, verify that the schema and data exist:

```bash
docker exec mysql-produccion mysql -uroot -p -e "SHOW TABLES FROM sakila;"
docker exec mysql-produccion mysql -uroot -p -e "SELECT COUNT(*) AS film_count FROM sakila.film;"
docker exec mysql-produccion mysql -uroot -p -e "SELECT COUNT(*) AS customer_count FROM sakila.customer;"
```

Enter the container's configured password when prompted. Avoid putting real passwords directly into shell commands or committing credentials to Git.

## 3. Configure and run the backup script

Review `scripts/respaldo.sh` and make sure its container names, database name, and credential handling match your local setup.

Make it executable and run a test:

```bash
chmod +x scripts/respaldo.sh
./scripts/respaldo.sh
```

The script should:

1. Check that both MySQL containers are available.
2. Create a timestamped SQL dump from the production database.
3. Check that the dump file is not empty.
4. Recreate the destination schema and import the dump into the backup instance.
5. Verify that expected tables and records are present.
6. Append status messages to `logs/respaldo.log`.

Inspect generated files and logs:

```bash
ls -lh backups/
tail -n 50 logs/respaldo.log
```

**Destructive restore warning:** the lab script drops and recreates the destination schema before importing. Confirm that the destination contains no unique data you need to preserve.

## 4. Schedule the workflow with `launchd`

Create a user LaunchAgent plist under:

```text
~/Library/LaunchAgents/
```

Configure it to run the absolute path to `scripts/respaldo.sh` daily at the chosen time. Replace any example username and paths with your actual macOS paths.

Validate the plist:

```bash
plutil -lint ~/Library/LaunchAgents/com.usuario.respaldo.plist
```

Load it for the current user:

```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.usuario.respaldo.plist
```

Check its status:

```bash
launchctl print gui/$(id -u)/com.usuario.respaldo
```

To unload it:

```bash
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.usuario.respaldo.plist
```

The Mac must be on and the Docker services must be available for a scheduled run to succeed. A user LaunchAgent may not run while the user is logged out. For a real production system, add monitoring, failure alerts, retry handling, protected secrets, and off-device backup storage.

## 5. Validate the restored data

Compare counts in both instances:

```bash
docker exec mysql-produccion mysql -uroot -p -e "SELECT COUNT(*) FROM sakila.film;"
docker exec mysql-respaldo mysql -uroot -p -e "SELECT COUNT(*) FROM sakila.film;"
```

Repeat for other tables, such as `customer` or `rental`. The counts should match if the source did not change during the backup and restore operation.

For additional evidence, insert a controlled test record into the source, run the script again, and verify that the record appears in the backup database. Use only test data and remember that each restore replaces the destination schema.

## 6. Evidence for the technical report

Capture real screenshots of:

- Both MySQL containers running
- The public sample database and its tables
- Source table counts
- The generated SQL backup file
- Successful script output and log entries
- Matching source and destination counts
- The `launchd` schedule configuration and status

Store screenshots in `evidencias/` if you intend to include them in the repository. Review each image for passwords, access tokens, personal information, or other sensitive content before committing.

## Security notes

- The credentials in a local lab configuration are examples only.
- Do not commit passwords, `.env` files containing secrets, private keys, or production data.
- Prefer a dedicated least-privilege MySQL account instead of `root`.
- Use a secure secrets mechanism or a protected client option file rather than hard-coding passwords in scripts.
- Store backups on a separate device or remote storage for protection against host or disk failure.
- Define a retention policy and test restoration regularly.
- A successful command is not a substitute for a tested recovery plan.

## References

- MySQL Sakila sample database: https://dev.mysql.com/doc/sakila/en/
- MySQL `mysqldump` documentation: https://dev.mysql.com/doc/refman/8.0/en/mysqldump.html
- Docker documentation: https://docs.docker.com/
- Apple launchd overview: https://www.launchd.info/

## License

Choose a license before publishing this repository publicly. If the repository is for a course assignment, follow your instructor's requirements.
