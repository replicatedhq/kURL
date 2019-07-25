FROM python:2

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    shunit2 && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /usr/src/app
WORKDIR /usr/src/app

COPY requirements.txt /usr/src/app/
RUN pip install --no-cache-dir --src /usr/local/src -r requirements.txt

COPY . /usr/src/app

ENV ENVIRONMENT dev

EXPOSE 5001

CMD ["python", "main.py"]
