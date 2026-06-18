package dev.u9g.minecraftdatagenerator.generators;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import dev.u9g.minecraftdatagenerator.util.DGU;
import net.minecraft.core.Registry;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.Identifier;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.entity.AgeableMob;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntitySpawnReason;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.Mob;
import net.minecraft.world.entity.ambient.AmbientCreature;
import net.minecraft.world.entity.animal.Animal;
import net.minecraft.world.entity.animal.fish.WaterAnimal;
import net.minecraft.world.entity.monster.Monster;
import net.minecraft.world.entity.projectile.Projectile;

public class EntitiesDataGenerator implements IDataGenerator {
    public static JsonObject generateEntity(Registry<EntityType<?>> entityRegistry, EntityType<?> entityType) {
        JsonObject entityDesc = new JsonObject();
        Identifier registryKey = entityRegistry.getKey(entityType);
        int entityRawId = entityRegistry.getId(entityType);

        entityDesc.addProperty("id", entityRawId);
        entityDesc.addProperty("internalId", entityRawId);
        entityDesc.addProperty("name", registryKey.getPath());

        entityDesc.addProperty("displayName", DGU.translateText(entityType.getDescriptionId()));
        entityDesc.addProperty("width", entityType.getDimensions().width());
        entityDesc.addProperty("height", entityType.getDimensions().height());

        String entityTypeString = "UNKNOWN";
        MinecraftServer minecraftServer = DGU.getCurrentlyRunningServer();

        if (minecraftServer != null) {
            Entity entityObject = entityType.create(minecraftServer.overworld(), EntitySpawnReason.NATURAL);
            entityTypeString = entityObject != null ? getEntityTypeForClass(entityObject.getClass()) : "unknown";
        }
        if (entityType == EntityType.PLAYER) {
            entityTypeString = "player";
        }

        entityDesc.addProperty("type", entityTypeString);
        entityDesc.addProperty("category", getCategoryFrom(entityType));

        return entityDesc;
    }

    private static String getCategoryFrom(EntityType<?> entityType) {
        if (entityType == EntityType.PLAYER) return "UNKNOWN";
        Entity entity = entityType.create(DGU.getWorld(), EntitySpawnReason.NATURAL);
        if (entity == null)
            throw new Error("Entity was null after trying to create a: " + DGU.translateText(entityType.getDescriptionId()));
        entity.discard();
        String packageName = entity.getClass().getPackageName();

        // Use a more flexible approach to handle sub-packages
        if (packageName.equals("net.minecraft.world.entity.decoration") ||
            packageName.startsWith("net.minecraft.world.entity.decoration.")) {
            return "Immobile";
        } else if (packageName.equals("net.minecraft.world.entity.boss") ||
                   packageName.equals("net.minecraft.world.entity.monster") ||
                   packageName.startsWith("net.minecraft.world.entity.boss.") ||
                   packageName.startsWith("net.minecraft.world.entity.monster.")) {
            return "Hostile mobs";
        } else if (packageName.equals("net.minecraft.world.entity.projectile") ||
                   packageName.startsWith("net.minecraft.world.entity.projectile.")) {
            return "Projectiles";
        } else if (packageName.equals("net.minecraft.world.entity.animal") ||
                   packageName.startsWith("net.minecraft.world.entity.animal.")) {
            return "Passive mobs";
        } else if (packageName.equals("net.minecraft.world.entity.vehicle") ||
                   packageName.startsWith("net.minecraft.world.entity.vehicle.")) {
            return "Vehicles";
        } else if (packageName.equals("net.minecraft.world.entity")) {
            return "UNKNOWN";
        } else {
            // Instead of throwing an error, return UNKNOWN for unexpected packages
            return "UNKNOWN";
        }
    }

    //Honestly, both "type" and "category" fields in the schema and examples do not contain any useful information
    //Since category is optional, I will just leave it out, and for type I will assume general entity classification
    //by the Entity class hierarchy (which has some weirdness too by the way)
    private static String getEntityTypeForClass(Class<? extends Entity> entityClass) {
        //Top-level classifications
        if (WaterAnimal.class.isAssignableFrom(entityClass)) {
            return "water_creature";
        }
        if (Animal.class.isAssignableFrom(entityClass)) {
            return "animal";
        }
        if (Monster.class.isAssignableFrom(entityClass)) {
            return "hostile";
        }
        if (AmbientCreature.class.isAssignableFrom(entityClass)) {
            return "ambient";
        }

        //Second level classifications. PathAwareEntity is not included because it
        //doesn't really make much sense to categorize by it
        if (AgeableMob.class.isAssignableFrom(entityClass)) {
            return "passive";
        }
        if (Mob.class.isAssignableFrom(entityClass)) {
            return "mob";
        }

        //Other classifications only include living entities and projectiles. everything else is categorized as other
        if (LivingEntity.class.isAssignableFrom(entityClass)) {
            return "living";
        }
        if (Projectile.class.isAssignableFrom(entityClass)) {
            return "projectile";
        }
        return "other";
    }

    @Override
    public String getDataName() {
        return "entities";
    }

    @Override
    public JsonArray generateDataJson() {
        JsonArray resultArray = new JsonArray();
        Registry<EntityType<?>> entityTypeRegistry = DGU.getWorld().registryAccess().lookupOrThrow(Registries.ENTITY_TYPE);
        entityTypeRegistry.forEach(entity -> resultArray.add(generateEntity(entityTypeRegistry, entity)));
        return resultArray;
    }
}
