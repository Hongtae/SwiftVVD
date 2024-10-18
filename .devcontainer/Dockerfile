FROM swift:latest

USER root

RUN apt-get update

RUN apt-get install -y git
RUN apt-get install -y git-lfs

RUN apt-get install -y vulkan-tools
RUN apt-get install -y libvulkan-dev
RUN apt-get install -y spirv-tools

RUN apt-get install -y libwayland-dev
RUN apt-get install -y libasound2-dev

USER devcontainer
