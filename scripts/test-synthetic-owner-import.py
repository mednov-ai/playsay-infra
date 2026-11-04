"""Exercise PostgreSQL 17.11 pg_dump/restore with a non-superuser synthetic owner."""

import json
import subprocess
import time
import uuid

task = "hs-owner-import-" + uuid.uuid4().hex[:10]
containers = []
network = None


def docker(*args, input_data=None, timeout=120):
    return subprocess.run(["docker", *args], input=input_data, capture_output=True,
                          text=True, check=True, timeout=timeout).stdout.strip()


def run_db(name, image, *args):
    result = docker("run", "-d", "--name", name, "--label", f"playsay-task={task}",
                    "--network", network, "--cpus", "0.5", "--memory", "256m", "--pull=never", *args, image)
    containers.append(result)
    return result


def wait_ready(container, *args):
    for _ in range(45):
        result = subprocess.run(["docker", "exec", container, "pg_isready", *args],
                                capture_output=True, timeout=5)
        if result.returncode == 0:
            return
        time.sleep(2)
    raise RuntimeError("synthetic PostgreSQL did not become ready")


try:
    network = docker("network", "create", "--internal", "--label", f"playsay-task={task}", task)
    source = run_db(task + "-source", "postgres@sha256:ef257d85f76e48da1c64832459b59fcaba1a4dac97bf5d7450c77753542eee94", "-e", "POSTGRES_PASSWORD=synthetic-admin-only")
    wait_ready(source, "-U", "postgres")
    docker("exec", source, "psql", "-X", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1",
           "-c", "CREATE ROLE fixture_owner LOGIN PASSWORD 'synthetic-owner-only'")
    docker("exec", source, "psql", "-X", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1",
           "-c", "CREATE DATABASE identity_fixture OWNER fixture_owner")
    docker("exec", "-e", "PGPASSWORD=synthetic-owner-only", source, "psql", "-X", "-h", "127.0.0.1",
           "-U", "fixture_owner", "-d", "identity_fixture", "-v", "ON_ERROR_STOP=1", "-c",
           "CREATE TABLE sample (id integer PRIMARY KEY, word varchar(80)); INSERT INTO sample VALUES (1, 'синтетический пример');")
    target = docker("run", "-d", "--name", task + "-target", "--label", f"playsay-task={task}",
                    "--network", network, "--cpus", "0.5", "--memory", "256m", "--pull=never", "--user", "26:26",
                    "--entrypoint", "sh", "ghcr.io/cloudnative-pg/postgresql@sha256:03a1c6a62b27e8ad31cae5c085131b5ac706b09403d6fcb6c58d16c8daa257cd", "-ec",
                    "initdb -D /tmp/fixture-db -U postgres --auth=trust --encoding=UTF8 --locale=C >/dev/null; "
                    "exec postgres -D /tmp/fixture-db -c listen_addresses= -c unix_socket_directories=/tmp "
                    "-c shared_buffers=32MB -c max_connections=10")
    containers.append(target)
    wait_ready(target, "-h", "/tmp", "-U", "postgres")
    owner_superuser = docker("exec", "-e", "PGPASSWORD=synthetic-owner-only", target, "psql", "-X",
                             "-h", task + "-source", "-U", "fixture_owner", "-d", "postgres", "-Atq", "-c",
                             "SELECT rolsuper FROM pg_roles WHERE rolname=current_user")
    if owner_superuser != "f":
        raise RuntimeError("fixture source user must not be a superuser")
    docker("exec", "-e", "PGPASSWORD=synthetic-owner-only", target, "pg_dump", "-Fd", "-j", "1",
           "-h", task + "-source", "-U", "fixture_owner", "-d", "identity_fixture", "-f", "/tmp/fixture-dump")
    docker("exec", target, "psql", "-X", "-h", "/tmp", "-U", "postgres", "-d", "postgres", "-v",
           "ON_ERROR_STOP=1", "-c", "CREATE ROLE fixture_owner LOGIN")
    docker("exec", target, "createdb", "-h", "/tmp", "-U", "postgres", "-O", "fixture_owner", "identity_fixture")
    docker("exec", target, "pg_restore", "--exit-on-error", "--no-owner", "--no-privileges",
           "--role=fixture_owner", "-h", "/tmp", "-U", "postgres", "-d", "identity_fixture", "/tmp/fixture-dump")
    check = docker("exec", target, "psql", "-X", "-h", "/tmp", "-U", "postgres", "-d", "identity_fixture",
                   "-Atq", "-c", "SELECT count(*)=1 AND max(char_length(word))=20 FROM sample")
    if check != "t":
        raise RuntimeError("synthetic row or UTF-8 length did not survive restore")
    print(json.dumps({"source": "PostgreSQL 17.6 synthetic", "destination": "PostgreSQL 17.11 synthetic",
                      "source_superuser": False, "owner_dump_restore": "passed"}))
finally:
    for container in reversed(containers):
        try:
            label = docker("inspect", "--format", '{{ index .Config.Labels "playsay-task" }}', container)
            if label == task:
                subprocess.run(["docker", "stop", "-t", "5", container], capture_output=True, timeout=20)
                docker("container", "rm", container)
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
            print("Synthetic container cleanup requires inspection.")
    if network:
        try:
            label = docker("network", "inspect", "--format", '{{ index .Labels "playsay-task" }}', network)
            if label == task:
                docker("network", "rm", network)
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
            print("Synthetic network cleanup requires inspection.")
