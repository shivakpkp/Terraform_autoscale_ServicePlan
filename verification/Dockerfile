FROM python:3.12-slim
WORKDIR /verification
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY conftest.py test_deployment.py expected.json ./
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
CMD ["python", "-m", "pytest", "-v", "--tb=short", "-p", "no:cacheprovider", "--junitxml=/results/results.xml"]
