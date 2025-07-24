

### CREAM
## continuous recording, easy access to media

The purpose of this project is to provide a "remote recording and media-serving" platform which can be used to trigger recording of audio from any attached USB microphones, and serve these recordings over an easy to use web interface.

CREAM uses the turbo.lua framework [1] for its asynchronous system event and http handling capabilities.

With CREAM, a user can connect to an embedded Linux system and trigger audio recordings remotely, with immediate access to captured media via the web interface.

I currently use the clockworkPi uConsole [2] paired with an Austrian Audio miCreator microphone [3] for development.  Multimple microphones can be configured per host, providing an ideal recording solution for conference and meeting applications, or even for studio/musician/creative environments.

The goal is eventually to add an IPFS gateway to CREAM, so that any media recorded through the CREAM system immediately becomes available on the Interplanetary Filesystem.

## Current status:

In active development - all basic I/O features are implemented, including remote recording, management of a media pool, and serving of media files over a web interface.  

I am currently in the middle of integrating the wonderful wavesurfer.js front-end UI framework [4], to give more fine-grained access to media, such as regions, silence detection, thumbnail navigation of media files, and so on.

The CREAM project is intended to target embedded Linux platforms, specifically for ARM - but will run pretty well on non-embedded Linux distributions as well.  A debian (.deb) target is provided in order to make installation on any Debian-like Linux distro very easy.

[1] https://turbo.readthedocs.io/en/latest/

[2] https://www.clockworkpi.com/home-uconsole

[3] https://de.austrian.audio/product/micreator-studio/

[4] https://wavesurfer.xyz
