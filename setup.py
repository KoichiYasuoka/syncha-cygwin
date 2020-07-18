import setuptools
import glob
import platform
if platform.system().startswith("CYGWIN"):
  if platform.machine()=="x86_64":
    data_files=[("local/bin",glob.glob("bin64/*")+glob.glob("bin/*"))]
    install_requires=["cabocha-cygwin64@git+https://github.com/KoichiYasuoka/cabocha-cygwin64"]
  else:
    data_files=[("local/bin",glob.glob("bin32/*")+glob.glob("bin/*"))]
    install_requires=["cabocha-cygwin32@git+https://github.com/KoichiYasuoka/cabocha-cygwin32"]
else:
  raise OSError("syncha-cygwin only for Cygwin")

data_files.append(("local/syncha",["syncha/syncha"]))
data_files.append(("local/syncha/src",glob.glob("syncha/src/*.pl")))
data_files.append(("local/syncha/dat/cooc",glob.glob("syncha/dat/cooc/*.tsv")))
for d in glob.glob("syncha/dat/model/*"):
  data_files.append(("local/"+d,glob.glob(d+"/*")))

setuptools.setup(
  name="syncha-cygwin",
  version="0.2.1",
  packages=setuptools.find_packages(),
  data_files=data_files,
  install_requires=install_requires
)
