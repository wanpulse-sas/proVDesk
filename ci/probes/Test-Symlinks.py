"""Check Flutter's directory symlink requirement before expensive builds."""
import pathlib
import tempfile


with tempfile.TemporaryDirectory(prefix="symlink-probe-", dir="build-tools") as directory:
    root = pathlib.Path(directory).resolve()
    target = root / "target"
    target.mkdir()
    link = root / "link"
    try:
        link.symlink_to(target, target_is_directory=True)
    except OSError as error:
        raise SystemExit(
            "Flutter requires directory symlink privileges for the build account. "
            "Use an elevated build process or enable Windows Developer Mode. "
            f"Windows error: {error}"
        ) from error
    if not link.is_symlink() or link.resolve() != target:
        raise SystemExit("Directory symlink validation failed.")
    link.unlink()
print("Flutter directory symlink creation: OK")
