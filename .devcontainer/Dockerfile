FROM swift:latest
RUN userdel -f -r ubuntu

USER root

RUN apt-get update

RUN apt-get install -y git
RUN apt-get install -y git-lfs

# Install system dependencies
RUN apt-get install -y vulkan-tools
RUN apt-get install -y libwayland-dev
RUN apt-get install -y libasound2-dev

# Install tools for downloading and extracting Vulkan SDK
RUN apt-get install -y xz-utils curl jq

# Download, extract and setup Vulkan SDK
WORKDIR /opt/vulkan-sdk
RUN echo "Fetching latest Vulkan SDK version..." && \
    SDK_VERSION=$(curl -s https://vulkan.lunarg.com/sdk/latest/linux.json | jq -r '.linux') && \
    if [ -z "${SDK_VERSION}" ] || [ "${SDK_VERSION}" = "null" ]; then \
        echo "Failed to fetch latest version, using fallback..."; \
        SDK_VERSION="1.4.328.1"; \
    fi && \
    echo "Latest Vulkan SDK version: ${SDK_VERSION}" && \
    SDK_URL="https://sdk.lunarg.com/sdk/download/${SDK_VERSION}/linux/vulkansdk-linux-x86_64-${SDK_VERSION}.tar.xz" && \
    echo "Vulkan SDK URL: ${SDK_URL}" && \
    echo "Downloading Vulkan SDK..." && \
    curl -L -k -O ${SDK_URL} && \
    tar -xf vulkansdk-linux-x86_64-${SDK_VERSION}.tar.xz && \
    rm vulkansdk-linux-x86_64-${SDK_VERSION}.tar.xz && \
    chmod +x ${SDK_VERSION}/setup-env.sh && \
    mkdir -p /etc/profile.d && \
    echo "source /opt/vulkan-sdk/${SDK_VERSION}/setup-env.sh" >> /etc/profile.d/vulkan.sh && \
    # Set environment variables globally
    PLATFORM_ARCH=$(uname -m) && \
    VULKAN_SDK="/opt/vulkan-sdk/${SDK_VERSION}/${PLATFORM_ARCH}" && \
    # Save SDK_VERSION and PLATFORM_ARCH to hidden files
    #echo "${SDK_VERSION}" > .version && \
    #echo "${PLATFORM_ARCH}" > .arch && \
    ln -s ${SDK_VERSION} latest && \
    ln -s ${SDK_VERSION}/${PLATFORM_ARCH} latest_root && \
    echo "Vulkan SDK ${SDK_VERSION} installed successfully"

#ENV VULKAN_SDK=/opt/vulkan-sdk/latest_root
#ENV PATH=$VULKAN_SDK/bin:$PATH
#ENV LD_LIBRARY_PATH=$VULKAN_SDK/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
#ENV VK_LAYER_PATH=$VULKAN_SDK/share/vulkan/explicit_layer.d

USER devcontainer
