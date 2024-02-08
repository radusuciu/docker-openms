# docker-openms

[OpenMS](https://github.com/OpenMS/OpenMS) is a C++ library for working with data LC-MS experiments and comes with a wide variety of tools. This project is not affiliated with OpenMS and it exists to scratch my own itch for building docker images for various releases or individual commits of [OpenMS](https://github.com/OpenMS/OpenMS).

This is based off work I've [contributed upstream](https://github.com/OpenMS/OpenMS/pull/7303), with some differences:
- I install dependencies using `apt`. See [this discussion](https://github.com/OpenMS/OpenMS/discussions/7302) for some background
- I am building my own boost packages and using a different version than the one in the main repository. This is based on work by Uli Köhler (https://github.com/ulikoehler/deb-buildscripts).
- based on Debian instead of Ubuntu
- built without GUI support
- built with static boost

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
