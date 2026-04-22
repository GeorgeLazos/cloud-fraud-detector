# Start small python image
FROM python:3.12-slim

# Set the working directory in the container (create app directory)
WORKDIR /app

# Install Java (required for PySpark)
RUN apt-get update && \
    apt-get install -y --no-install-recommends openjdk-17-jre-headless && \
    rm -rf /var/lib/apt/lists/*

# Assign environment variables for Java and Spark
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ENV SPARK_LOCAL_HOSTNAME=localhost

# Install python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Copy the application code to the container and create necessary directories
COPY scripts ./scripts
RUN mkdir -p data output

# BASE IMAGE'S DEFAULT CMD STAYS ON TRAINING. THE SCORING IMAGE OVERRIDES CMD VIA Dockerfile.scoring
# (DOC 2: IMAGE LAYERING - DERIVED IMAGES PIN A DIFFERENT ENTRYPOINT/CMD WITHOUT REBUILDING DEPENDENCIES).

#Set the default command to run the application
CMD ["python", "scripts/fraud_detection_pyspark.py", "--data-path", "data/creditcard.csv", "--output-dir", "output", "--max-iter", "10"]
