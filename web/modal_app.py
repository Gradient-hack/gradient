"""Modal deployment entrypoint for the Sidewalk walking podcast demo."""

import modal


app = modal.App("gradient-walking-podcast")

image = (
    modal.Image.debian_slim(python_version="3.13")
    .uv_sync()
    .add_local_python_source("main", "gemini_proxy", "walk_demo")
    .add_local_file("index.html", "/root/index.html")
    .add_local_dir("assets", "/root/assets")
)

google_secret = modal.Secret.from_name(
    "gradient-google",
    required_keys=["GOOGLE_API_KEY"],
)


@app.function(
    image=image,
    secrets=[google_secret],
    timeout=60 * 60,
    scaledown_window=300,
    max_containers=2,
    region="eu",
    routing_region="eu-west",
)
@modal.concurrent(max_inputs=8, target_inputs=4)
@modal.asgi_app()
def web():
    from main import app as fastapi_app

    return fastapi_app
