from setuptools import setup, find_packages

setup(
    name="finals_classifier",
    version="0.1.0",
    packages=find_packages(include=["syllable*", "pianyin*"]),
    package_dir={"": "."},
    package_data={
        "syllable.analysis.slice": ["yinyuan/*.json"],
    },
    python_requires=">=3.8",
    install_requires=[],
)
