FROM ghcr.io/cirruslabs/flutter:3.29.0

# RUN #apt-get update
# RUN #apt-get install -y curl git unzip xz-utils zip libglu1-mesa wget
# RUN #apt-get install -y curl libc6:amd64 libstdc++6:amd64 lib32z1 libbz2-1.0:amd64
#WORKDIR /development
# RUN #wget -O flutter.tar.xz https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.29.0-stable.tar.xz
# RUN #tar -xf flutter.tar.xz
# RUN #git config --global --add safe.directory /development/flutter
#ENV PATH "$PATH:/development/flutter/bin"

COPY . /app
#WORKDIR /app/android
#RUN ./gradlew clean

WORKDIR /app
RUN flutter build apk --release


CMD ["flutter", "run"]