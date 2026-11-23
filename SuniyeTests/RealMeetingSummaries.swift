/// Summaries that the two summary models wrote in the summary eval: Apple
/// Intelligence and the local model, on a 45-minute and a 2-hour meeting.
enum RealMeetingSummaries {
    static let all: [String] = [
        #"""
        ## Overview
        The meeting was about shipping version 2.4 and addressing user feedback on performance, navigation, and design. The team decided on several actions based on error reports, help center usability, sign-in confusion, search results, and sync service wording.

        ## Decisions
        - Shipping version 2.4 on Friday
        - Priya will write the release notes
        - Error reports feels slow on a weak connection
        - Help center hard to find from the main menu
        - Sign-in page confuses new users
        - Dark theme looks fine on large screen but cramped on small one
        - Empty states hard to find from the main menu
        - Search results confuses new users
        - Sync service still shows old wording on second step
        - Team settings behaves better since last change
        - Billing page hard to find from the main menu
        - Sync service gets fewer complaints than before
        - Error reports looks fine on large screen but cramped on small one
        - Help center got mixed reactions in interviews
        - Sign-in page works but nobody loves it
        - Team settings reads well but labels are long
        - Empty states got mixed reactions in interviews
        - Billing page got mixed reactions in interviews
        - Search results works but nobody loves it
        - Error reports feels slow on weak connection
        - Help center hard to find from main menu
        - Empty states hard to find from main menu
        - Sync service shows old wording on second step
        - Billing page hard to find from main menu
        - The Android widget is dropped from this release
        - The team settings behaves better since the last change
        - The dark theme feels slow on a weak connection

        ## Action items
        - Priya will write the release notes
        - [User] to review the sign-in page confusion for new users by the third of December
        - [User] to investigate the search results confusion for new users
        - [User] to check the help center findability from the main menu

        ## Dates and numbers
        - Friday
        - The next review is on the third of December

        ## Open questions
        - Is the dark theme slow on a weak connection?
        - Is the empty states hard to find from the main menu?
        - Is the error reports slow on a weak connection?
        - Why does the error reports feel slow on a weak connection?
        - Why does the sync service still show the old wording on the second step?
        - Why does the dark theme look fine on a large screen but cramped on a small one?
        """#,
        #"""
        ## Overview
        The meeting was about planning the release of version 2.4 and assigning tasks related to it. A decision was made to ship version 2.4 on Friday.

        ## Decisions
        - We decided to ship version 2.4 on Friday.

        ## Action items
        - Priya will write the release notes.
        - Marco owns the database migration and finishes it by Wednesday.

        ## Dates and numbers
        - 2.4: version to be shipped on Friday.
        - Wednesday: Marco to finish the database migration.
        - third of December

        ## Open questions
        - I am not sure about that.
        """#,
        #"""
        ## Overview
        The meeting was about shipping version 2.4, reviewing user feedback on various features, and deciding on changes to interface elements and service performance. The team agreed on several technical adjustments and confirmed ongoing tasks.

        ## Decisions
        - Ship version 2.4 on Friday.
        - The help center got mixed reactions in the interviews
        - The search results works, although nobody loves it
        - The dark theme looks fine on a large screen but cramped on a small one
        - The team settings reads well, but the labels are long; agree to keep labels as they are.
        - The dark theme looks fine on a large screen but cramped on a small one; agree to maintain this view.
        - The error reports looks fine on a large screen but cramped on a small one; agree to keep this layout.
        - The help center got mixed reactions in the interviews; agree to consider feedback.
        - The sync service gets fewer complaints than it used to
        - The error reports feels slow on a weak connection
        - The team settings behaves better since the last change
        - The billing page is hard to find from the main menu
        - The sign-in page works, although nobody loves it
        - The empty states is hard to find from the main menu
        - The sync service still shows the old wording on the second step
        - The error reports looks fine on a large screen but cramped on a small one
        - The sign-in page confuses people who are new to the product
        - The team settings reads well, but the labels are long
        - The billing page got mixed reactions in the interviews
        - The help center is hard to find from the main menu
        - The empty states got mixed reactions in the interviews
        - The search results confuses people who are new to the product
        - The dark theme feels slow on a weak connection
        - The team agrees the dark theme feels slow on a weak connection
        - The team agrees the error reports feels slow on a weak connection
        - The team agrees the search results works, although nobody loves it
        - Drop the Android widget from this release
        - Keep the dark theme on large screens but not on small ones
        - Keep the error reports on large screens but not on small ones
        - Keep the help center on large screens but not on small ones
        - Keep the search results on large screens but not on small ones
        - Keep the sign-in page on large screens but not on small ones
        - Keep the sync service on large screens but not on small ones
        - Keep the team settings since the last change
        - Sync service gets fewer complaints than it used to
        - Error reports feels slow on a weak connection
        - Team settings behaves better since the last change.
        - Help center got mixed reactions in the interviews
        - Sign-in page works, although nobody loves it

        ## Action items
        - Them: Ship version 2.4 on Friday.
        - Priya will write the release notes
        - [Them] will review the search results to improve clarity for new users by [date not specified].
        - [Them] will check the sync service to ensure it shows the updated wording on the second step by [date not specified].
        - Marco owns the database migration and finishes it by Wednesday
        - You will drop the Android widget from this release
        - You will keep the dark theme on large screens but not on small ones
        - You will keep the error reports on large screens but not on small ones
        - You will keep the help center on large screens but not on small ones
        - You will keep the search results on large screens but not on small ones
        - You will keep the sign-in page on large screens but not on small ones
        - You will keep the sync service on large screens but not on small ones
        - You will keep the team settings since the last change
        - Review the search results by the third of December
        - Find the billing page from the main menu by the third of December.
        - Them will check the dark theme speed on a weak connection by now
        - Them will confirm if empty states are hard to find from the main menu by next week
        - Them will verify if the billing page is hard to find from the main menu by end of month.

        ## Dates and numbers
        - Friday: Ship version 2.4.
        - [date not specified]: The team settings reads well, but the labels are long.
        - [date not specified]: The dark theme looks fine on a large screen but cramped on a small one.
        - [date not specified]: The error reports looks fine on a large screen but cramped on a small one.
        - Wednesday: Marco finishes the database migration
        - 6 of 8
        - Third of December: next review.
        - 1 (the last change)
        - next week
        - end of month.

        ## Open questions
        - Is the dark theme slow on a weak connection?
        - Does the help center get mixed reactions in the interviews?
        - Is the sign-in page confusing for new users?
        - Does the empty states page get mixed reactions in the interviews?
        - Does the sync service still show the old wording on the second step?
        - What does Priya plan to write?
        - Is the error reports slow on a weak connection?
        - Why does the dark theme feel slow on a weak connection?
        - Why is the empty states hard to find from the main menu?
        - Why does the search results work but nobody loves it?
        - Is the dark theme slow on a weak connection for everyone?
        - Is the billing page hard to find from the main menu?
        - What does the dark theme feel like on a weak connection?
        - What does the empty states look like from the main menu?
        - What does the sync service show on the second step?
        - Does the empty states page get found from the main menu?
        - Who will find the empty states from the main menu?
        - Who will confirm if the search results confuses new users?
        - Who will check if the error reports is slow on a weak connection?
        """#,
        #"""
        ## Overview
        The meeting was about decisions regarding a software release and assigned action items. It was decided to ship version 2.4 on Friday.

        ## Decisions
        - We decided to ship version 2.4 on Friday.

        ## Action items
        - Priya will write the release notes
        - Priya
        - not specified
        - Marco owns the database migration and finishes it by Wednesday.

        ## Dates and numbers
        - Friday: ship version 2.4
        - pilot budget is forty thousand dollars
        - Wednesday: Marco to finish the database migration.
        - The next review is on the third of December.

        ## Open questions
        - I am not sure about that.
        """#,
    ]
}
