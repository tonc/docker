### 阶段 1: 构建环境 (Builder) —— 包含完整开发工具链
FROM nvidia/cudagl:10.2-devel-ubuntu16.04 AS builder

# 元数据与基础配置
ENV TZ=Asia/Shanghai \
    DEBIAN_FRONTEND=noninteractive
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 系统级依赖安装（合并APT操作）
RUN apt-get update && apt-get install -y \
    build-essential cmake git wget \
    python3-pip python3-dev \
    libglm-dev libsuitesparse-dev \
    && rm -rf /var/lib/apt/lists/*

# 配置国内镜像源加速
RUN sed -i 's/archive.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list && \
    pip3 config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple

# ROS Kinetic 安装（使用清华镜像）
RUN sh -c 'echo "deb http://mirrors.tuna.tsinghua.edu.cn/ros/ubuntu/ xenial main" > /etc/apt/sources.list.d/ros-latest.list' \
    && apt-key adv --keyserver 'hkp://keyserver.ubuntu.com:80' --recv-key C1CF6E31E6BADE8868B172B4F42ED6FBAB17C654 \
    && apt-get update && apt-get install -y \
    ros-kinetic-desktop-full \
    ros-kinetic-moveit \
    ros-kinetic-ros-control \
    && rm -rf /var/lib/apt/lists/*

# Python依赖安装（通过requirements.txt管理）
COPY requirements.txt .
RUN pip3 install -r requirements.txt

# 第三方库编译安装（Eigen/g2o/NLopt）
RUN wget https://gitlab.com/libeigen/eigen/-/archive/3.3.7/eigen-3.3.7.tar.gz \
    && tar -xzvf eigen-3.3.7.tar.gz \
    && mkdir eigen-3.3.7/build && cd eigen-3.3.7/build \
    && cmake .. && make install

RUN git clone https://github.com/RainerKuemmerle/g2o /usr/local/g2o \
    && cd /usr/local/g2o \
    && mkdir build && cd build \
    && cmake .. && make && make install

RUN git clone https://github.com/stevengj/nlopt \
    && cd nlopt && mkdir build && cd build \
    && cmake .. && make && make install

### 阶段 2: 运行时环境 (Runtime) —— 最小化镜像
FROM nvidia/cudagl:10.2-runtime-ubuntu16.04

# 从构建阶段复制编译结果
COPY --from=builder /usr/local/include/eigen3 /usr/local/include/eigen3
COPY --from=builder /usr/local/lib/libg2o* /usr/local/lib/
COPY --from=builder /usr/local/lib/libnlopt* /usr/local/lib/

# 系统运行时依赖
RUN apt-get update && apt-get install -y \
    python3-pip libglm-dev \
    ros-kinetic-desktop-full \
    ros-kinetic-moveit \
    ros-kinetic-ros-control \
    ros-kinetic-serial \
    && rm -rf /var/lib/apt/lists/*

# SSH 服务配置（安全增强版）
ARG SSH_PORT=4399
ARG SSH_PASSWORD=ChangeMe123!
RUN apt-get update && apt-get install -y openssh-server \
    && sed -i "s/#Port 22/Port $SSH_PORT/" /etc/ssh/sshd_config \
    && sed -i "s/PermitRootLogin prohibit-password/PermitRootLogin yes/" /etc/ssh/sshd_config \
    && echo "root:$SSH_PASSWORD" | chpasswd \
    && mkdir -p /var/run/sshd

# GUI 环境变量配置
COPY entrypoint.sh /usr/local/bin/
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/usr/sbin/sshd", "-D"]

# 工作区初始化
RUN mkdir -p /root/vscode-workspace/sign_language_robot_ws
