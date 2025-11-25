# Test dict iteration with .items(), .keys(), .values()
routes = {"/home": "home_handler", "/about": "about_handler", "/contact": "contact_handler"}

print("All routes:")
for path, handler in routes.items():
    print(path)
    print(handler)

print("Paths only:")
for path in routes.keys():
    print(path)

print("Handlers only:")
for handler in routes.values():
    print(handler)
