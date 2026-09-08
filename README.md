# docker-openms

[OpenMS](https://github.com/OpenMS/OpenMS) is a C++ library for working with data LC-MS experiments and comes with a wide variety of tools. This project is not affiliated with OpenMS and it exists to scratch my own itch for building docker images for various releases or individual commits of [OpenMS](https://github.com/OpenMS/OpenMS).

This is based off work I've [contributed upstream](https://github.com/OpenMS/OpenMS/pull/7303), with some differences:
- I install dependencies using `apt`. See [this discussion](https://github.com/OpenMS/OpenMS/discussions/7302) for some background
- based on Debian instead of Ubuntu
- built without GUI support
- removed example files

These changes were made in an effort to minimize the size of the image for my application. At time of writing the image is 459MB, almost 2x smaller than the official image. Any advice on shrinking this further would be much appreciated!

### A note on boost

This project used to build its own boost packages (based on work by Uli Köhler,
https://github.com/ulikoehler/deb-buildscripts) and link them statically. That is
no longer the case: we use the boost that Debian ships.

Two things make the distro package the better choice:

- Debian bookworm ships boost 1.74, which is exactly the minimum OpenMS asks for
  (`find_package(Boost 1.74.0 ... REQUIRED CONFIG)`) and exactly the version
  upstream builds and tests `release/3.4.1` against (Ubuntu 22.04). Some tests --
  `MRMAssay_test` in particular -- compare against reference data that depends on
  boost implementation details (`boost::unordered_map` iteration order, and
  `boost::uniform_int` over `boost::mt19937` for decoy sequence generation), so
  matching the version upstream validates against matters.
- Debian's `libboost_*.a` are not built with `-fPIC`, so they cannot be linked
  into `libOpenMS.so`. That is why `-DBOOST_USE_STATIC=OFF` is now passed, which
  is also what upstream does. The cost is ~1.2MB of shared libraries in the
  runtime image; `libicu` is already pulled in by xerces/Qt, so it adds nothing.

## Use

To pull images, you can use the following command, substituting the image name and tag as described above.

```shell
docker pull ghcr.io/radusuciu/docker-openms:3.1.0
```

Here's an example on running an tool:

```shell
docker run -t --rm ghcr.io/radusuciu/docker-openms:3.1.0 IsobaricAnalyzer -h
```

The above command should output the help-text for `IsobaricAnalyzer`, and the container will be removed after. If you want to work on files in the directory you're issuing the command from, you can mount the directory as volume like so:

```shell
# downloading a file so this example works
wget https://github.com/OpenMS/OpenMS/raw/develop/share/OpenMS/examples/BSA/BSA1.mzML
docker run -t --rm -v "$PWD:/data" ghcr.io/radusuciu/docker-openms:3.1.0 FileInfo -in /data/BSA1.mzML
```

For ease of use, you can even alias the above command. On linux you can add the following to your  `~/.bash_aliases` or `.bashrc` files:

```shell
alias openms='docker run -t --rm -v "$PWD:/data" ghcr.io/radusuciu/docker-openms:3.1.0'
```

which will make the command significantly shorter: `openms FileInfo -in /data/BSA1.mzML`
