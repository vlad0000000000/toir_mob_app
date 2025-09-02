FROM ghcr.io/cirruslabs/flutter:3.29.0

RUN apt-get update
RUN apt-get remove -y openjdk-21-jdk
RUN apt-get install -y openjdk-17-jdk

ENV JAVA_HOME /usr/lib/jvm/java-17-openjdk-amd64
RUN export JAVA_HOME

COPY . /app

WORKDIR /app
#RUN flutter build apk --release


CMD ["flutter", "run"]