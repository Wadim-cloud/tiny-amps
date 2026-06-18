from setuptools import setup, find_packages

with open("README.md", "r") as fh:
    long_description = fh.read()

setup(
    name="tiny-amps",
    version="0.1.0",
    author="Wadim-cloud",
    description="High-performance in-memory pub/sub hub in Odin with Python/ctypes bindings",
    long_description=long_description,
    long_description_content_type="text/markdown",
    packages=find_packages(where="py"),
    package_dir={"": "py"},
    package_data={
        "amps": ["*.so", "*.dylib", "*.dll"],
    },
    include_package_data=True,
    python_requires=">=3.7",
    install_requires=[],
    extras_require={
        "dev": ["pytest>=6.0"],
    },
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Programming Language :: Python :: 3",
        "Programming Language :: Odin",
        "Topic :: System :: Distributed Computing",
    ],
)
