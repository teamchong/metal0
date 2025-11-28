# Test datetime module
import datetime

# Test datetime.datetime.now()
now = datetime.datetime.now()
print("now:", now)

# Test datetime.date.today()
today = datetime.date.today()
print("today:", today)

# Test datetime.timedelta
delta = datetime.timedelta(7)
print("timedelta(7):", delta)
