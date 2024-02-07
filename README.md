# docker-openms

[OpenMS](https://github.com/OpenMS/OpenMS) is a C++ library for working with data LC-MS experiments and comes with a wide variety of tools. This project is not affiliated with OpenMS and it exists to scratch my own itch for building docker images for various releases or individual commits of [OpenMS](https://github.com/OpenMS/OpenMS).

This is based off work I've [contributed upstream](https://github.com/OpenMS/OpenMS/pull/7303), with some differences:
- I install dependencies using `apt`. See [this discussion](https://github.com/OpenMS/OpenMS/discussions/7302) for some background
- I am building my own boost packages and using a different version than the one in the main repository. This is based on work by Uli Köhler (https://github.com/ulikoehler/deb-buildscripts).
