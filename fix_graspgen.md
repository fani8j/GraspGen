# GraspGen Fix Notes for RTX 5070 Ti (CUDA 12.8)

This file summarizes the commands needed to fix and rerun the GraspGen setup on a machine like this one.

## Assumptions

- Repo path: `~/GraspGen`
- Virtual environment: `~/GraspGen/.venv`
- GPU: RTX 5070 Ti
- CUDA toolkit installed at `/usr/local/cuda` and pointing to CUDA 12.8
- You are running from the repo root

---

## 1. Activate environment and export CUDA variables

```bash
cd ~/GraspGen
source .venv/bin/activate

export CUDA_HOME=/usr/local/cuda
export PATH=$CUDA_HOME/bin:$PATH
export LD_LIBRARY_PATH=$CUDA_HOME/lib64:$LD_LIBRARY_PATH
export TORCH_CUDA_ARCH_LIST="7.5;8.0;8.6;9.0;10.0;12.0"

hash -r
/usr/local/cuda/bin/nvcc --version
python -c "import torch; print(torch.__version__); print(torch.version.cuda)"
```

---

## 2. Install the working PyTorch version

```bash
uv pip uninstall -y torch torchvision torchaudio torch-scatter torch_sparse torch_cluster torch_spline_conv pyg-lib
uv pip install torch==2.8.0 torchvision==0.23.0 torchaudio==2.8.0 --index-url https://download.pytorch.org/whl/cu128
uv pip install torch-scatter -f https://data.pyg.org/whl/torch-2.8.0+cu128.html
```

---

## 3. Patch `pointnet2_ops` in site-packages

This removes the old hardcoded CUDA arch list that included `3.7`.

```bash
python - <<'PY'
from pathlib import Path

p = Path(".venv/lib/python3.10/site-packages/pointnet2_ops/pointnet2_utils.py")
s = p.read_text()

old = '    os.environ["TORCH_CUDA_ARCH_LIST"] = "3.7+PTX;5.0;6.0;6.1;6.2;7.0;7.5"'
new = '    os.environ.setdefault("TORCH_CUDA_ARCH_LIST", "7.5;8.0;8.6;9.0;10.0;12.0")'

if old in s:
    s = s.replace(old, new)
    p.write_text(s)
    print("Patched", p)
else:
    print("No change needed in", p)
PY
```

---

## 4. Patch GraspGen PointNet2 fallback path

This fixes the fallback JIT compile path so it uses the installed `pointnet2_ops` source tree instead of looking in the wrong repo path.

```bash
python - <<'PY'
from pathlib import Path

p = Path("grasp_gen/models/pointnet/pointnet2_utils.py")
s = p.read_text()

old = '''    _ext_src_root = osp.join(osp.dirname(__file__), "_ext-src")
    _ext_sources = glob.glob(osp.join(_ext_src_root, "src", "*.cpp")) + glob.glob(
        osp.join(_ext_src_root, "src", "*.cu")
    )

    # os.environ["TORCH_CUDA_ARCH_LIST"] = "3.7+PTX;5.0;6.0;6.1;6.2;7.0;7.5"
    ops = load(
        "_ext",
        sources=_ext_sources,
        extra_include_paths=[osp.join(_ext_src_root, "include")],
        extra_cflags=["-O3"],
        extra_cuda_cflags=["-O3", "-Xfatbin", "-compress-all"],
        with_cuda=True,
    )
'''

new = '''    import pointnet2_ops

    _ext_src_root = osp.join(osp.dirname(pointnet2_ops.__file__), "_ext-src")
    _ext_sources = glob.glob(osp.join(_ext_src_root, "src", "*.cpp")) + glob.glob(
        osp.join(_ext_src_root, "src", "*.cu")
    )

    ops = load(
        "_ext",
        sources=_ext_sources,
        extra_include_paths=[osp.join(_ext_src_root, "include")],
        extra_cflags=["-O3"],
        extra_cuda_cflags=["-O3", "-Xfatbin", "-compress-all"],
        with_cuda=True,
    )
'''

if old in s:
    s = s.replace(old, new)
    p.write_text(s)
    print("Patched", p)
else:
    print("Target block not found or already patched in", p)
PY
```

---

## 5. Clear old compiled extension cache

```bash
rm -rf ~/.cache/torch_extensions
rm -f .venv/lib/python3.10/site-packages/pointnet2_ops/_ext*.so
find . -type d -name build -exec rm -rf {} +
find . -type d -name dist -exec rm -rf {} +
find . -type d -name "*.egg-info" -exec rm -rf {} +
```

---

## 6. Verify imports

```bash
python -c "import torch; print(torch.__version__); print(torch.version.cuda)"
python -c "import torch_scatter; print(torch_scatter.__file__)"
python -c "from torch.utils.cpp_extension import CUDA_HOME; print(CUDA_HOME)"
```

---

## 7. Run the installation test

```bash
python tests/test_inference_installation.py
```

Expected result: all 4 tests pass.

---

## 8. Run the demo mesh inference

```bash
python scripts/demo_object_mesh.py \
  --mesh_file GraspGenModels/sample_data/meshes/box.obj \
  --mesh_scale 1.0 \
  --gripper_config GraspGenModels/checkpoints/graspgen_robotiq_2f_140.yml \
  --output_file grasps_out
```

If it works, you should see output similar to:

- model checkpoints loaded
- mesh processed
- 100 grasps inferred
- grasps saved to the file you specified

---

## 9. Optional: make CUDA vars persistent

Add this to `~/.bashrc`:

```bash
export CUDA_HOME=/usr/local/cuda
export PATH=$CUDA_HOME/bin:$PATH
export LD_LIBRARY_PATH=$CUDA_HOME/lib64:$LD_LIBRARY_PATH
export TORCH_CUDA_ARCH_LIST="7.5;8.0;8.6;9.0;10.0;12.0"
```

Then reload:

```bash
source ~/.bashrc
```

---

## 10. One-shot rerun block

```bash
cd ~/GraspGen
source .venv/bin/activate

export CUDA_HOME=/usr/local/cuda
export PATH=$CUDA_HOME/bin:$PATH
export LD_LIBRARY_PATH=$CUDA_HOME/lib64:$LD_LIBRARY_PATH
export TORCH_CUDA_ARCH_LIST="7.5;8.0;8.6;9.0;10.0;12.0"

uv pip uninstall -y torch torchvision torchaudio torch-scatter torch_sparse torch_cluster torch_spline_conv pyg-lib
uv pip install torch==2.8.0 torchvision==0.23.0 torchaudio==2.8.0 --index-url https://download.pytorch.org/whl/cu128
uv pip install torch-scatter -f https://data.pyg.org/whl/torch-2.8.0+cu128.html

python - <<'PY'
from pathlib import Path

p = Path(".venv/lib/python3.10/site-packages/pointnet2_ops/pointnet2_utils.py")
s = p.read_text()
old = '    os.environ["TORCH_CUDA_ARCH_LIST"] = "3.7+PTX;5.0;6.0;6.1;6.2;7.0;7.5"'
new = '    os.environ.setdefault("TORCH_CUDA_ARCH_LIST", "7.5;8.0;8.6;9.0;10.0;12.0")'
if old in s:
    p.write_text(s.replace(old, new))
    print("Patched", p)
else:
    print("No change needed in", p)
PY

python - <<'PY'
from pathlib import Path

p = Path("grasp_gen/models/pointnet/pointnet2_utils.py")
s = p.read_text()
old = '''    _ext_src_root = osp.join(osp.dirname(__file__), "_ext-src")
    _ext_sources = glob.glob(osp.join(_ext_src_root, "src", "*.cpp")) + glob.glob(
        osp.join(_ext_src_root, "src", "*.cu")
    )

    # os.environ["TORCH_CUDA_ARCH_LIST"] = "3.7+PTX;5.0;6.0;6.1;6.2;7.0;7.5"
    ops = load(
        "_ext",
        sources=_ext_sources,
        extra_include_paths=[osp.join(_ext_src_root, "include")],
        extra_cflags=["-O3"],
        extra_cuda_cflags=["-O3", "-Xfatbin", "-compress-all"],
        with_cuda=True,
    )
'''
new = '''    import pointnet2_ops

    _ext_src_root = osp.join(osp.dirname(pointnet2_ops.__file__), "_ext-src")
    _ext_sources = glob.glob(osp.join(_ext_src_root, "src", "*.cpp")) + glob.glob(
        osp.join(_ext_src_root, "src", "*.cu")
    )

    ops = load(
        "_ext",
        sources=_ext_sources,
        extra_include_paths=[osp.join(_ext_src_root, "include")],
        extra_cflags=["-O3"],
        extra_cuda_cflags=["-O3", "-Xfatbin", "-compress-all"],
        with_cuda=True,
    )
'''
if old in s:
    p.write_text(s.replace(old, new))
    print("Patched", p)
else:
    print("Target block not found or already patched in", p)
PY

rm -rf ~/.cache/torch_extensions
rm -f .venv/lib/python3.10/site-packages/pointnet2_ops/_ext*.so

python tests/test_inference_installation.py
```

---

## Final known-good state

- CUDA toolkit: 12.8
- PyTorch: `2.8.0+cu128`
- `torch_scatter` installed for `torch-2.8.0+cu128`
- `pointnet2_ops` patched
- GraspGen PointNet fallback patched
- installation test passes
- demo mesh inference runs successfully
