/****************************************************
				EXTERNAL ORGANS
****************************************************/
/obj/item/organ/external
	name = "external"
	min_broken_damage = 30
	max_damage = 0
	dir = SOUTH
	organ_tag = "limb"

	var/brute_mod = 1
	var/burn_mod = 1

	var/icon_name = null
	var/body_part = null
	var/icon_position = 0

	var/model
	var/force_icon

	var/icobase = 'icons/mob/human_races/r_human.dmi'		// Normal icon set.
	var/deform = 'icons/mob/human_races/r_def_human.dmi'	// Mutated icon set.

	var/damage_state = "00"
	var/brute_dam = 0
	var/burn_dam = 0
	var/max_size = 0
	var/icon/mob_icon
	var/gendered_icon = 0
	var/limb_name
	var/disfigured = 0
	var/cannot_amputate
	var/cannot_break
	var/s_tone = null
	var/list/s_col = null // If this is instantiated, it should be a list of length 3
	var/list/child_icons = list()
	var/perma_injury = 0
	var/dismember_at_max_damage = FALSE

	var/obj/item/organ/external/parent
	var/list/obj/item/organ/external/children
	var/list/convertable_children = list()

	// Internal organs of this body part
	var/list/internal_organs = list()

	var/damage_msg = "<span class='warning'>You feel an intense pain</span>"
	var/broken_description

	var/open = 0
	var/sabotaged = 0 //If a prosthetic limb is emagged, it will detonate when it fails.
	var/encased       // Needs to be opened with a saw to access the organs.

	var/obj/item/hidden = null
	var/list/embedded_objects = list()
	var/internal_bleeding = FALSE
	var/amputation_point // Descriptive string used in amputation.
	var/can_grasp
	var/can_stand

/obj/item/organ/external/necrotize(update_sprite=TRUE)
	if(status & (ORGAN_ROBOT|ORGAN_DEAD))
		return
	status |= ORGAN_DEAD
	if(dead_icon)
		icon_state = dead_icon
	if(owner)
		to_chat(owner, "<span class='notice'>You can't feel your [name] anymore...</span>")
		owner.update_body(update_sprite)
		if(vital)
			owner.death()

/obj/item/organ/external/Destroy()
	if(parent && parent.children)
		parent.children -= src

	parent = null

	if(internal_organs)
		for(var/obj/item/organ/internal/O in internal_organs)
			internal_organs -= O
			O.remove(owner,special = 1)
			qdel(O)

	if(owner)
		owner.bodyparts_by_name[limb_name] = null

	QDEL_LIST(children)

	QDEL_LIST(embedded_objects)

	QDEL_NULL(hidden)

	return ..()

/obj/item/organ/external/attackby(obj/item/weapon/W as obj, mob/user as mob)
	switch(open)
		if(0)
			if(istype(W,/obj/item/weapon/scalpel))
				spread_germs_to_organ(src,user, W)
				user.visible_message("<span class='danger'><b>[user]</b> cuts [src] open with [W]!</span>")
				open++
				return
		if(1)
			if(istype(W,/obj/item/weapon/retractor))
				spread_germs_to_organ(src,user, W)
				user.visible_message("<span class='danger'><b>[user]</b> cracks [src] open like an egg with [W]!</span>")
				open++
				return
		if(2)
			if(istype(W,/obj/item/weapon/hemostat))
				spread_germs_to_organ(src,user, W)
				if(contents.len)
					var/obj/item/removing = pick(contents)
					var/obj/item/organ/internal/O = removing
					if(istype(O))
						if(!O.sterile)
							spread_germs_to_organ(O,user, W) // This wouldn't be any cleaner than the actual surgery
					user.put_in_hands(removing)
					user.visible_message("<span class='danger'><b>[user]</b> extracts [removing] from [src] with [W]!</span>")
				else
					user.visible_message("<span class='danger'><b>[user]</b> fishes around fruitlessly in [src] with [W].</span>")
				return
	. = ..()


/obj/item/organ/external/update_health()
	damage = min(max_damage, (brute_dam + burn_dam))
	return


/obj/item/organ/external/New(var/mob/living/carbon/holder)
	..()
	var/mob/living/carbon/human/H = holder
	icobase = species.icobase
	deform = species.deform
	if(istype(H))
		replaced(H)
		sync_colour_to_human(H)
	spawn(1)
		get_icon()

/obj/item/organ/external/replaced(var/mob/living/carbon/human/target)
	owner = target
	forceMove(owner)
	if(istype(owner))
		if(!isnull(owner.bodyparts_by_name[limb_name]))
			log_debug("Duplicate organ in slot \"[limb_name]\", mob '[target]'")
		owner.bodyparts_by_name[limb_name] = src
		owner.bodyparts |= src
		for(var/atom/movable/stuff in src)
			stuff.attempt_become_organ(src, owner)

	if(parent_organ)
		parent = owner.bodyparts_by_name[src.parent_organ]
		if(parent)
			if(!parent.children)
				parent.children = list()
			parent.children.Add(src)
			parent.check_fracture()

/obj/item/organ/external/attempt_become_organ(obj/item/organ/external/parent,mob/living/carbon/human/H)
	if(parent_organ != parent.limb_name)
		return 0
	replaced(H)
	return 1

/****************************************************
			   DAMAGE PROCS
****************************************************/

/obj/item/organ/external/take_damage(brute, burn, sharp, used_weapon = null, list/forbidden_limbs = list(), ignore_resists = FALSE)
	if(tough && !ignore_resists)
		brute = max(0, brute - 5)
		burn = max(0, burn - 4)

	if((brute <= 0) && (burn <= 0))
		return 0

	if(!ignore_resists)
		brute *= brute_mod
		burn *= burn_mod

	// Threshold needed to have a chance of hurting internal bits with something sharp
#define LIMB_SHARP_THRESH_INT_DMG 5
	// Threshold needed to have a chance of hurting internal bits
#define LIMB_THRESH_INT_DMG 10
	// Probability of taking internal damage from sufficient force, while otherwise healthy
#define LIMB_DMG_PROB 5
	// High brute damage or sharp objects may damage internal organs
	if(internal_organs && (brute_dam >= max_damage || (((sharp && brute >= LIMB_SHARP_THRESH_INT_DMG) || brute >= LIMB_THRESH_INT_DMG) && prob(LIMB_DMG_PROB))))
		// Damage an internal organ
		if(internal_organs && internal_organs.len)
			var/obj/item/organ/internal/I = pick(internal_organs)
			if(!I.tough)//mostly for cybernetic organs
				I.take_damage(brute / 2)
			brute -= brute / 2

	if(status & ORGAN_BROKEN && prob(40) && brute)
		owner.emote("scream")	//getting hit on broken hand hurts
	if(used_weapon)
		add_autopsy_data("[used_weapon]", brute + burn)

	// Make sure we don't exceed the maximum damage a limb can take before dismembering
	if((brute_dam + burn_dam + brute + burn) < max_damage)
		brute_dam += brute
		burn_dam += burn
		check_for_internal_bleeding(brute)
	else
		//If we can't inflict the full amount of damage, spread the damage in other ways
		//How much damage can we actually cause?
		var/can_inflict = max_damage - (brute_dam + burn_dam)
		if(can_inflict)
			if(brute > 0)
				//Inflict all burte damage we can
				brute_dam = min(brute_dam + brute, brute_dam + can_inflict)
				var/temp = can_inflict
				//How much mroe damage can we inflict
				can_inflict = max(0, can_inflict - brute)
				//How much brute damage is left to inflict
				brute = max(0, brute - temp)
				check_for_internal_bleeding(brute)

			if(burn > 0 && can_inflict)
				//Inflict all burn damage we can
				burn_dam = min(burn_dam + burn, burn_dam + can_inflict)
				//How much burn damage is left to inflict
				burn = max(0, burn - can_inflict)
		//If there are still hurties to dispense
		if(burn || brute)
			//List organs we can pass it to
			var/list/obj/item/organ/external/possible_points = list()
			if(parent)
				possible_points += parent
			if(children)
				for(var/organ in children)
					if(organ)
						possible_points += organ
			if(forbidden_limbs.len)
				possible_points -= forbidden_limbs
			if(possible_points.len)
				//And pass the pain around
				var/obj/item/organ/external/target = pick(possible_points)
				target.take_damage(brute, burn, sharp, used_weapon, forbidden_limbs + src, ignore_resists = TRUE) //If the damage was reduced before, don't reduce it again

			if(dismember_at_max_damage && body_part != UPPER_TORSO && body_part != LOWER_TORSO) // We've ensured all damage to the mob is retained, now let's drop it, if necessary.
				droplimb(1) //Clean loss, just drop the limb and be done

	// See if bones need to break
	check_fracture()
	var/mob/living/carbon/owner_old = owner //Need to update health, but need a reference in case the below check cuts off a limb.
	//If limb took enough damage, try to cut or tear it off
	if(owner && loc == owner)
		if(!cannot_amputate && (brute_dam) >= (max_damage))
			if(prob(brute / 2))
				if(sharp)
					droplimb(0, DROPLIMB_SHARP)

	if(owner_old)
		owner_old.updatehealth()
	return update_icon()

#undef LIMB_SHARP_THRESH_INT_DMG
#undef LIMB_THRESH_INT_DMG
#undef LIMB_DMG_PROB
#undef LIMB_NO_BONE_DMG_PROB

/obj/item/organ/external/proc/heal_damage(brute, burn, internal = 0, robo_repair = 0)
	if(status & ORGAN_ROBOT && !robo_repair)
		return

	brute_dam = max(brute_dam - brute, 0)
	burn_dam  = max(burn_dam - burn, 0)

	if(internal)
		status &= ~ORGAN_BROKEN
		perma_injury = 0

	owner.updatehealth()

	return update_icon()

/*
This function completely restores a damaged organ to perfect condition.
*/
/obj/item/organ/external/rejuvenate()
	damage_state = "00"
	if(status & ORGAN_ROBOT)	//Robotic organs stay robotic.
		status = ORGAN_ROBOT
	else if(status & ORGAN_ASSISTED) //Assisted organs stay assisted.
		status = ORGAN_ASSISTED
	else
		status = 0
	germ_level = 0
	perma_injury = 0
	brute_dam = 0
	burn_dam = 0
	open = 0 //Closing all wounds.
	internal_bleeding = FALSE
	if(istype(src, /obj/item/organ/external/head) && disfigured) //If their head's disfigured, refigure it.
		disfigured = 0

	// handle internal organs
	for(var/obj/item/organ/internal/current_organ in internal_organs)
		current_organ.rejuvenate()

	for(var/obj/item/organ/external/EO in contents)
		EO.rejuvenate()

	owner.updatehealth()
	update_icon()
	if(!owner)
		processing_objects |= src

/****************************************************
			   PROCESSING & UPDATING
****************************************************/

//Determines if we even need to process this organ.

/obj/item/organ/external/process()
	if(owner)
		//Chem traces slowly vanish
		if(owner.life_tick % 10 == 0)
			for(var/chemID in trace_chemicals)
				trace_chemicals[chemID] = trace_chemicals[chemID] - 1
				if(trace_chemicals[chemID] <= 0)
					trace_chemicals.Remove(chemID)

		if(!(status & ORGAN_BROKEN))
			perma_injury = 0

		//Infections
		update_germs()
	else
		..()

//Updating germ levels. Handles organ germ levels and necrosis.
/*
The INFECTION_LEVEL values defined in setup.dm control the time it takes to reach the different
infection levels. Since infection growth is exponential, you can adjust the time it takes to get
from one germ_level to another using the rough formula:

desired_germ_level = initial_germ_level*e^(desired_time_in_seconds/1000)

So if I wanted it to take an average of 15 minutes to get from level one (100) to level two
I would set INFECTION_LEVEL_TWO to 100*e^(15*60/1000) = 245. Note that this is the average time,
the actual time is dependent on RNG.

INFECTION_LEVEL_ONE		below this germ level nothing happens, and the infection doesn't grow
INFECTION_LEVEL_TWO		above this germ level the infection will start to spread to internal and adjacent organs
INFECTION_LEVEL_THREE	above this germ level the player will take additional toxin damage per second, and will die in minutes without
						antitox. also, above this germ level you will need to overdose on spaceacillin to reduce the germ_level.

Note that amputating the affected organ does in fact remove the infection from the player's body.
*/
/obj/item/organ/external/proc/update_germs()

	if((status & ORGAN_ROBOT) || (IS_PLANT in owner.species.species_traits)) //Robotic limbs shouldn't be infected, nor should nonexistant limbs.
		germ_level = 0
		return

	if(owner.bodytemperature >= 170)	//cryo stops germs from moving and doing their bad stuffs
		//** Syncing germ levels with external wounds
		handle_germ_sync()

		//** Handle antibiotics and curing infections
		handle_antibiotics()

		//** Handle the effects of infections
		handle_germ_effects()

/obj/item/organ/external/proc/handle_germ_sync()
	var/antibiotics = owner.reagents.get_reagent_amount("spaceacillin")
	if(antibiotics < 5)
		//Open wounds can become infected
		if(owner.germ_level > germ_level && infection_check())
			germ_level++

/obj/item/organ/external/handle_germ_effects()

	if(germ_level < INFECTION_LEVEL_TWO)
		return ..()

	var/antibiotics = owner.reagents.get_reagent_amount("spaceacillin")

	if(germ_level >= INFECTION_LEVEL_TWO)
		//spread the infection to internal organs
		var/obj/item/organ/internal/target_organ = null	//make internal organs become infected one at a time instead of all at once
		for(var/obj/item/organ/internal/I in internal_organs)
			if(I.germ_level > 0 && I.germ_level < min(germ_level, INFECTION_LEVEL_TWO))	//once the organ reaches whatever we can give it, or level two, switch to a different one
				if(!target_organ || I.germ_level > target_organ.germ_level)	//choose the organ with the highest germ_level
					target_organ = I

		if(!target_organ)
			//figure out which organs we can spread germs to and pick one at random
			var/list/candidate_organs = list()
			for(var/obj/item/organ/internal/I in internal_organs)
				if(I.germ_level < germ_level)
					candidate_organs |= I
			if(candidate_organs.len)
				target_organ = pick(candidate_organs)

		if(target_organ)
			target_organ.germ_level++

		//spread the infection to child and parent organs
		if(children)
			for(var/obj/item/organ/external/child in children)
				if(child.germ_level < germ_level && !(child.status & ORGAN_ROBOT))
					if(child.germ_level < INFECTION_LEVEL_ONE*2 || prob(30))
						child.germ_level++

		if(parent)
			if(parent.germ_level < germ_level && !(parent.status & ORGAN_ROBOT))
				if(parent.germ_level < INFECTION_LEVEL_ONE*2 || prob(30))
					parent.germ_level++

	if(germ_level >= INFECTION_LEVEL_THREE && antibiotics < 30)	//overdosing is necessary to stop severe infections
		necrotize()

		germ_level++
		owner.adjustToxLoss(1)

//Updates brute_damn and burn_damn from wound damages. Updates BLEEDING status.
/obj/item/organ/external/proc/check_fracture()
	if(config.bones_can_break && brute_dam > min_broken_damage && !(status & ORGAN_ROBOT))
		fracture()

/obj/item/organ/external/proc/check_for_internal_bleeding(damage)
	var/local_damage = brute_dam + damage
	if(damage > 15 && local_damage > 30 && prob(damage) && !(status & ORGAN_ROBOT))
		internal_bleeding = TRUE
		owner.custom_pain("You feel something rip in your [name]!", 1)

// new damage icon system
// returns just the brute/burn damage code
/obj/item/organ/external/proc/damage_state_text()
	var/tburn = 0
	var/tbrute = 0

	if(burn_dam ==0)
		tburn =0
	else if(burn_dam < (max_damage * 0.25 / 2))
		tburn = 1
	else if(burn_dam < (max_damage * 0.75 / 2))
		tburn = 2
	else
		tburn = 3

	if(brute_dam == 0)
		tbrute = 0
	else if(brute_dam < (max_damage * 0.25 / 2))
		tbrute = 1
	else if(brute_dam < (max_damage * 0.75 / 2))
		tbrute = 2
	else
		tbrute = 3
	return "[tbrute][tburn]"

/****************************************************
			   DISMEMBERMENT
****************************************************/

//Handles dismemberment
/obj/item/organ/external/proc/droplimb(var/clean, var/disintegrate, var/ignore_children, var/nodamage)

	if(cannot_amputate || !owner)
		return

	if(!disintegrate)
		disintegrate = DROPLIMB_SHARP

	switch(disintegrate)
		if(DROPLIMB_SHARP)
			if(!clean)
				var/gore_sound = "[(status & ORGAN_ROBOT) ? "tortured metal" : "ripping tendons and flesh"]"
				owner.visible_message(
					"<span class='danger'>\The [owner]'s [src.name] flies off in an arc!</span>",\
					"<span class='moderate'><b>Your [src.name] goes flying off!</b></span>",\
					"<span class='danger'>You hear a terrible sound of [gore_sound].</span>")
		if(DROPLIMB_BURN)
			var/gore = "[(status & ORGAN_ROBOT) ? "": " of burning flesh"]"
			owner.visible_message(
				"<span class='danger'>\The [owner]'s [src.name] flashes away into ashes!</span>",\
				"<span class='moderate'><b>Your [src.name] flashes away into ashes!</b></span>",\
				"<span class='danger'>You hear a crackling sound[gore].</span>")
		if(DROPLIMB_BLUNT)
			var/gore = "[(status & ORGAN_ROBOT) ? "": " in shower of gore"]"
			var/gore_sound = "[(status & ORGAN_ROBOT) ? "rending sound of tortured metal" : "sickening splatter of gore"]"
			owner.visible_message(
				"<span class='danger'>\The [owner]'s [src.name] explodes[gore]!</span>",\
				"<span class='moderate'><b>Your [src.name] explodes[gore]!</b></span>",\
				"<span class='danger'>You hear the [gore_sound].</span>")

	var/mob/living/carbon/human/victim = owner //Keep a reference for post-removed().
	// Let people make limbs become fun things when removed
	var/atom/movable/dropped_part = remove(null, ignore_children)

	if(parent)
		parent.children -= src
		if(!nodamage)
			var/total_brute = brute_dam
			var/total_burn = burn_dam
			for(var/obj/item/organ/external/E in children) //Factor in the children's brute and burn into how much will transfer
				total_brute += E.brute_dam
				total_burn += E.burn_dam
			parent.take_damage(total_brute, total_burn, ignore_resists = TRUE) //Transfer the full damage to the parent, bypass limb damage reduction.
		parent = null

	spawn(1)
		if(victim)
			victim.updatehealth()
			victim.UpdateDamageIcon()
			victim.regenerate_icons()
		dir = 2
	switch(disintegrate)
		if(DROPLIMB_SHARP)
			compile_icon()
			add_blood(victim.blood_DNA, victim.species.blood_color)
			var/matrix/M = matrix()
			M.Turn(rand(180))
			src.transform = M
			if(!clean)
				// Throw limb around.
				if(src && istype(loc,/turf))
					dropped_part.throw_at(get_edge_target_turf(src,pick(alldirs)),rand(1,3),30)
				dir = 2
			brute_dam = 0
			burn_dam = 0  //Reset the damage on the limb; the damage should have transferred to the parent; we don't want extra damage being re-applie when then limb is re-attached
			return dropped_part
		else
			qdel(src) // If you flashed away to ashes, YOU FLASHED AWAY TO ASHES
			return null

/****************************************************
			   HELPERS
****************************************************/
/obj/item/organ/external/proc/release_restraints(var/mob/living/carbon/human/holder)
	if(!holder)
		holder = owner
	if(!holder)
		return
	if(holder.handcuffed && body_part in list(ARM_LEFT, ARM_RIGHT, HAND_LEFT, HAND_RIGHT))
		holder.visible_message(\
			"\The [holder.handcuffed.name] falls off of [holder.name].",\
			"\The [holder.handcuffed.name] falls off you.")
		holder.unEquip(holder.handcuffed)
	if(holder.legcuffed && body_part in list(FOOT_LEFT, FOOT_RIGHT, LEG_LEFT, LEG_RIGHT))
		holder.visible_message(\
			"\The [holder.legcuffed.name] falls off of [holder.name].",\
			"\The [holder.legcuffed.name] falls off you.")
		holder.unEquip(holder.legcuffed)

/obj/item/organ/external/proc/fracture()
	if(status & ORGAN_ROBOT)
		return	//ORGAN_BROKEN doesn't have the same meaning for robot limbs

	if((status & ORGAN_BROKEN) || cannot_break)
		return
	if(owner)
		owner.visible_message(\
			"<span class='warning'>You hear a loud cracking sound coming from \the [owner].</span>",\
			"<span class='danger'>Something feels like it shattered in your [name]!</span>",\
			"You hear a sickening crack.")
		if(owner.species && !(NO_PAIN in owner.species.species_traits))
			owner.emote("scream")

	status |= ORGAN_BROKEN
	broken_description = pick("broken","fracture","hairline fracture")
	perma_injury = brute_dam

	// Fractures have a chance of getting you out of restraints
	if(prob(25))
		release_restraints()

/obj/item/organ/external/proc/mend_fracture()
	if(status & ORGAN_ROBOT)
		return 0	//ORGAN_BROKEN doesn't have the same meaning for robot limbs
	if(brute_dam > min_broken_damage)
		return 0	//will just immediately fracture again

	status &= ~ORGAN_BROKEN
	return 1

/obj/item/organ/external/robotize(company, make_tough = 0, convert_all = 1)
	..()
	//robot limbs take reduced damage
	if(!make_tough)
		brute_mod = 0.66
		burn_mod = 0.66
		dismember_at_max_damage = TRUE
	else
		tough = 1
	// Robot parts also lack bones
	// This is so surgery isn't kaput, let's see how this does
	encased = null

	if(company && istext(company))
		set_company(company)

	cannot_break = 1
	get_icon()
	for(var/obj/item/organ/external/T in children)
		if((convert_all) || (T.type in convertable_children))
			T.robotize(company, make_tough, convert_all)



/obj/item/organ/external/proc/set_company(var/company)
	model = company
	var/datum/robolimb/R = all_robolimbs[company]
	if(R)
		force_icon = R.icon
		name = "[R.company] [initial(name)]"
		desc = "[R.desc]"

/obj/item/organ/external/proc/mutate()
	src.status |= ORGAN_MUTATED
	if(owner)
		owner.update_body(1, 1) //Forces all bodyparts to update in order to correctly render the deformed sprite.

/obj/item/organ/external/proc/unmutate()
	src.status &= ~ORGAN_MUTATED
	if(owner)
		owner.update_body(1, 1) //Forces all bodyparts to update in order to correctly return them to normal.

/obj/item/organ/external/proc/get_damage()	//returns total damage
	return max(brute_dam + burn_dam - perma_injury, perma_injury)	//could use health?

/obj/item/organ/external/proc/has_infected_wound()
	if(germ_level > INFECTION_LEVEL_ONE)
		return TRUE
	return FALSE

/obj/item/organ/external/proc/is_usable()
	if(((status & ORGAN_ROBOT) && get_damage() >= max_damage) && !tough) //robot limbs just become inoperable at max damage
		return
	return !(status & (ORGAN_MUTATED|ORGAN_DEAD))

/obj/item/organ/external/proc/is_malfunctioning()
	return ((status & ORGAN_ROBOT) && (brute_dam + burn_dam) >= 10 && prob(brute_dam + burn_dam) && !tough)

/obj/item/organ/external/remove(var/mob/living/user, var/ignore_children)

	if(!owner)
		return
	var/is_robotic = status & ORGAN_ROBOT
	var/mob/living/carbon/human/victim = owner

	for(var/obj/item/I in embedded_objects)
		embedded_objects -= I
		I.forceMove(src)
	if(!owner.has_embedded_objects())
		owner.clear_alert("embeddedobject")

	. = ..()

	// Attached organs also fly off.
	if(!ignore_children)
		for(var/obj/item/organ/external/O in children)
			var/atom/movable/thing = O.remove(victim)
			if(thing)
				thing.forceMove(src)

	// Grab all the internal giblets too.
	for(var/obj/item/organ/internal/organ in internal_organs)
		var/atom/movable/thing = organ.remove(victim)
		thing.forceMove(src)

	release_restraints(victim)
	victim.bodyparts -= src
	if(is_primary_organ(victim))
		victim.bodyparts_by_name[limb_name] = null	// Remove from owner's vars.

	//Robotic limbs explode if sabotaged.
	if(is_robotic && sabotaged)
		victim.visible_message(
			"<span class='danger'>\The [victim]'s [src.name] explodes violently!</span>",\
			"<span class='danger'>Your [src.name] explodes!</span>",\
			"<span class='danger'>You hear an explosion!</span>")
		explosion(get_turf(owner),-1,-1,2,3)
		var/datum/effect/system/spark_spread/spark_system = new /datum/effect/system/spark_spread()
		spark_system.set_up(5, 0, victim)
		spark_system.attach(owner)
		spark_system.start()
		spawn(10)
			qdel(spark_system)
		qdel(src)

/obj/item/organ/external/proc/disfigure(var/type = "brute")
	if(disfigured)
		return
	if(owner)
		if(type == "brute")
			owner.visible_message("<span class='warning'>You hear a sickening cracking sound coming from \the [owner]'s [name].</span>",	\
			"<span class='danger'>Your [name] becomes a mangled mess!</span>",	\
			"<span class='warning'>You hear a sickening crack.</span>")
		else
			owner.visible_message("<span class='warning'>\The [owner]'s [name] melts away, turning into mangled mess!</span>",	\
			"<span class='danger'>Your [name] melts away!</span>",	\
			"<span class='warning'>You hear a sickening sizzle.</span>")
	disfigured = 1

/obj/item/organ/external/is_primary_organ(var/mob/living/carbon/human/O = null)
	if(isnull(O))
		O = owner
	if(!istype(O)) // You're not the primary organ of ANYTHING, bucko
		return 0
	return src == O.bodyparts_by_name[limb_name]

/obj/item/organ/external/proc/infection_check()
	var/total_damage = brute_dam + burn_dam
	if(total_damage)
		if(total_damage < 10) //small amounts of damage aren't infectable
			return FALSE

		if(owner && owner.bleedsuppress && total_damage < 25)
			return FALSE

		var/dam_coef = round(total_damage / 10)
		return prob(dam_coef * 10)
	return FALSE

/obj/item/organ/external/serialize()
	var/list/data = ..()
	if(robotic == 2)
		data["company"] = model
	// If we wanted to store wound information, here is where it would go
	return data

/obj/item/organ/external/deserialize(list/data)
	var/company = data["company"]
	if(company && istext(company))
		set_company(company)
	..() // Parent call loads in the DNA
	if(data["dna"])
		sync_colour_to_dna()

//Remove all embedded objects from all limbs on the carbon mob
/mob/living/carbon/human/proc/remove_all_embedded_objects()
	var/turf/T = get_turf(src)

	for(var/X in bodyparts)
		var/obj/item/organ/external/L = X
		for(var/obj/item/I in L.embedded_objects)
			L.embedded_objects -= I
			I.forceMove(T)

	clear_alert("embeddedobject")

/mob/living/carbon/human/proc/has_embedded_objects()
	. = 0
	for(var/X in bodyparts)
		var/obj/item/organ/external/L = X
		for(var/obj/item/I in L.embedded_objects)
			return 1