class Test:
    def __init__(self, skip=None):
        super().__init__(skip=skip)
        self.skip = skip

if __name__ == "__main__":
    t = Test(skip="hello")
    print(t.skip)
